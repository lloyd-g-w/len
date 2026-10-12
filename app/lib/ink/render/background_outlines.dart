import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/stroke.dart';
import 'outline_preparer.dart';
import 'stroke_renderer.dart';

/// Builds outlines on worker isolates (spawned on first use) and on the UI
/// isolate between frames, and memoises them on the UI isolate.
///
/// A batch is cut into slices of [sliceSize] strokes, handed out in order
/// to the workers (two at a time each, so a worker never waits for the UI
/// isolate). The UI isolate turns their answers into paths and, while none
/// is waiting, builds outlines of the next strokes itself — a stroke at a
/// time, never more than [stepBudget] before yielding to the event loop
/// (and so to the next frame). Both matter on a phone or tablet: worker
/// threads run on slower cores than the UI thread (on the Galaxy Tab S8+
/// three workers together build about as many outlines per second as the
/// UI thread does in its spare time), and a large batch (a canvas of tens
/// of thousands of strokes) must neither stall a frame nor show nothing
/// until its last stroke is done: [OutlinePreparer.prepare]'s `onReady`
/// hears of every slice as soon as its paths exist. Only imported by
/// `platform/outline_preparer_native.dart`.
class BackgroundOutlines implements OutlinePreparer {
  BackgroundOutlines({
    this.workers = 2,
    this.sliceSize = 96,
    this.stepBudget = const Duration(milliseconds: 3),
    this.buildHere = true,
    this.hold,
  });

  /// Worker isolates to spread the work over.
  final int workers;

  /// Strokes per message to a worker.
  final int sliceSize;

  /// UI-isolate time one step may take before yielding.
  final Duration stepBudget;

  /// Whether the UI isolate builds outlines too while it has nothing to
  /// convert (off: only the workers build them; tests).
  final bool buildHere;

  /// While this answers true (the user is writing), the UI isolate builds
  /// no outlines itself — it only adopts the workers' — so pen input and
  /// pen-up are not queued behind that work.
  final bool Function()? hold;

  /// Strokes the UI isolate takes at a time.
  static const int hereSlice = 8;

  /// Batches smaller than this are built inline (not worth a round trip).
  static const int inlineBelow = 24;

  List<Future<SendPort?>>? _ports;
  final List<Isolate> _isolates = [];
  bool _closed = false;

  /// Batches being prepared, oldest first.
  final List<_Batch> _batches = [];

  /// Worker answers waiting to be turned into paths, oldest first.
  final Queue<_Answer> _answers = Queue();

  /// Whether a worker could not be started (the UI isolate builds all).
  bool _workerless = false;

  /// The slice the UI isolate is building itself, and how far it got.
  _Answer? _own;
  bool _running = false;

  @override
  Future<void> prepare(List<Stroke> strokes, {void Function(List<Stroke> ready)? onReady}) async {
    final todo = <Stroke>[];
    final done = <Stroke>[];
    for (final s in strokes) {
      (StrokeRenderer.hasPath(s) ? done : todo).add(s);
    }
    if (done.isNotEmpty) onReady?.call(done);
    if (todo.isEmpty) return;
    if (_closed || todo.length < inlineBelow) {
      await const InlineOutlinePreparer().prepare(todo, onReady: onReady);
      return;
    }
    final batch = _Batch(onReady, todo.length);
    for (var i = 0; i < todo.length; i += sliceSize) {
      batch.slices.add(todo.sublist(i, i + sliceSize > todo.length ? todo.length : i + sliceSize));
    }
    _batches.add(batch);
    final ports = _ports ??= List.generate(workers, _spawn);
    // Two loops per worker: one slice being built while the answer to the
    // other is on its way back.
    for (final port in ports) {
      for (var k = 0; k < 2; k++) {
        unawaited(_work(port, batch));
      }
    }
    if (buildHere) _wake();
    await batch.done.future;
  }

  /// Hands [batch]'s slices to the worker behind [port] until none is left.
  Future<void> _work(Future<SendPort?> port, _Batch batch) async {
    final worker = _closed ? null : await port;
    if (worker == null) {
      _workerless = true;
      _wake(); // The UI isolate builds them.
      return;
    }
    while (batch.slices.isNotEmpty && !_closed) {
      final slice = batch.slices.removeFirst();
      final reply = ReceivePort();
      worker.send((TransferableTypedData.fromList([_pack(slice)]), reply.sendPort));
      final answer = await reply.first;
      reply.close();
      if (answer is (TransferableTypedData, Int32List)) {
        final (data, ends) = answer;
        _answers.add(_Answer(batch, slice, data.materialize().asFloat64List(), ends));
      } else {
        _answers.add(_Answer(batch, slice, null, null)); // Built here instead.
      }
      _wake();
    }
    if (_closed) _wake();
  }

  /// Starts the UI isolate's loop unless it is running.
  void _wake() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  /// The UI isolate's share: worker answers first (cheap per stroke), then
  /// strokes no worker has taken yet; [stepBudget] at a time.
  Future<void> _run() async {
    final watch = Stopwatch()..start();
    developer.Timeline.startSync('len.outlineStep');
    try {
      while (true) {
        if (watch.elapsed > stepBudget) {
          developer.Timeline.finishSync();
          await Future<void>.delayed(Duration.zero);
          developer.Timeline.startSync('len.outlineStep');
          watch.reset();
        }
        final answer = _answers.isNotEmpty ? _answers.first : _own ?? _takeOwn();
        if (answer == null) return;
        final strokes = answer.strokes;
        if (answer.next < strokes.length) {
          final i = answer.next++;
          final stroke = strokes[i];
          if (!StrokeRenderer.hasPath(stroke)) {
            final commands = answer.commands;
            if (commands == null) {
              StrokeRenderer.pathOf(stroke);
            } else {
              final ends = answer.ends!;
              StrokeRenderer.adopt(
                stroke,
                OutlineCommands.toPath(
                  Float64List.sublistView(commands, i == 0 ? 0 : ends[i - 1], ends[i]),
                ),
              );
            }
          }
          continue;
        }
        if (identical(answer, _own)) {
          _own = null;
        } else {
          _answers.removeFirst();
        }
        answer.batch.report(strokes);
        if (answer.batch.done.isCompleted) _batches.remove(answer.batch);
      }
    } finally {
      developer.Timeline.finishSync();
      _running = false;
    }
  }

  /// A few strokes of the oldest batch that no worker has taken yet (all
  /// of them once the workers are gone).
  _Answer? _takeOwn() {
    for (final batch in _batches) {
      final slices = batch.slices;
      if (slices.isEmpty) continue;
      final all = _closed || _workerless;
      if (!all && (!buildHere || (hold?.call() ?? false))) return null;
      var slice = slices.removeFirst();
      if (slice.length > hereSlice && !all) {
        slices.addFirst(slice.sublist(hereSlice));
        slice = slice.sublist(0, hereSlice);
      }
      return _own = _Answer(batch, slice, null, null);
    }
    return null;
  }

  /// Per stroke: tool, width, the style's four numbers, the point count,
  /// then x, y, pressure of each point.
  static Float64List _pack(List<Stroke> strokes) {
    var length = 0;
    for (final s in strokes) {
      length += 7 + 3 * s.points.length;
    }
    final data = Float64List(length);
    var i = 0;
    for (final s in strokes) {
      final style = s.style;
      data
        ..[i++] = s.tool.index.toDouble()
        ..[i++] = s.width
        ..[i++] = style.opacity
        ..[i++] = style.thinning
        ..[i++] = style.streamline
        ..[i++] = style.unit
        ..[i++] = s.points.length.toDouble();
      for (final p in s.points) {
        data
          ..[i++] = p.x
          ..[i++] = p.y
          ..[i++] = p.pressure;
      }
    }
    return data;
  }

  static List<Stroke> _unpack(Float64List data) {
    final strokes = <Stroke>[];
    var i = 0;
    while (i < data.length) {
      final tool = InkTool.values[data[i].toInt()];
      final width = data[i + 1];
      final style = StrokeStyle(
        opacity: data[i + 2],
        thinning: data[i + 3],
        streamline: data[i + 4],
        unit: data[i + 5],
      );
      final n = data[i + 6].toInt();
      i += 7;
      strokes.add(
        Stroke(
          id: '',
          surfaceId: '',
          tool: tool,
          color: 0,
          width: width,
          style: style,
          createdAt: 0,
          points: [
            for (var k = 0; k < n; k++)
              StrokePoint(data[i + 3 * k], data[i + 3 * k + 1], data[i + 3 * k + 2]),
          ],
        ),
      );
      i += 3 * n;
    }
    return strokes;
  }

  Future<SendPort?> _spawn(int index) async {
    final ready = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_serve, ready.sendPort, debugName: 'outlines $index');
      _isolates.add(isolate);
      final port = await ready.first;
      return port is SendPort ? port : null;
    } on Object {
      return null;
    } finally {
      ready.close();
    }
  }

  static void _serve(SendPort ready) {
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) {
      final (packed, reply) = message as (TransferableTypedData, SendPort);
      try {
        final (all, ends) = OutlineCommands.ofAll(_unpack(packed.materialize().asFloat64List()));
        reply.send((TransferableTypedData.fromList([all]), ends));
      } on Object catch (e) {
        reply.send('$e');
      }
    });
  }

  @override
  void close() {
    _closed = true;
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
  }
}

/// One [BackgroundOutlines.prepare] call: the slices nobody has taken
/// yet, and how many strokes are still to come.
class _Batch {
  _Batch(this.onReady, this.remaining);

  final void Function(List<Stroke> ready)? onReady;
  final Queue<List<Stroke>> slices = Queue();
  int remaining;
  final Completer<void> done = Completer();

  void report(List<Stroke> strokes) {
    onReady?.call(strokes);
    remaining -= strokes.length;
    if (remaining <= 0 && !done.isCompleted) done.complete();
  }
}

/// Strokes whose outlines are being memoised: from a worker's [commands]
/// (each stroke ending at its entry in [ends]), or built here when those
/// are null; [next] is the first one not done yet.
class _Answer {
  _Answer(this.batch, this.strokes, this.commands, this.ends);

  final _Batch batch;
  final List<Stroke> strokes;
  final Float64List? commands;
  final Int32List? ends;
  int next = 0;
}
