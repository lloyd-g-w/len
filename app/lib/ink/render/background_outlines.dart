import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/stroke.dart';
import 'outline_preparer.dart';
import 'stroke_renderer.dart';

/// Builds outlines on worker isolates (spawned on first use), a share of
/// each batch per worker, and memoises them on the UI isolate. Only
/// imported by `platform/outline_preparer_native.dart`.
class BackgroundOutlines implements OutlinePreparer {
  BackgroundOutlines({this.workers = 2});

  /// Worker isolates to spread the work over.
  final int workers;

  /// Batches smaller than this are built inline (not worth a round trip).
  static const int inlineBelow = 24;

  List<Future<SendPort?>>? _ports;
  final List<Isolate> _isolates = [];
  bool _closed = false;

  @override
  Future<void> prepare(List<Stroke> strokes) async {
    final todo = [
      for (final s in strokes)
        if (!StrokeRenderer.hasPath(s)) s,
    ];
    if (todo.isEmpty) return;
    if (_closed || todo.length < inlineBelow) {
      await const InlineOutlinePreparer().prepare(todo);
      return;
    }
    final ports = _ports ??= List.generate(workers, _spawn);
    final share = (todo.length / ports.length).ceil();
    await Future.wait([
      for (var w = 0; w < ports.length; w++)
        if (w * share < todo.length)
          _build(
            ports[w],
            todo.sublist(w * share, (w + 1) * share > todo.length ? todo.length : (w + 1) * share),
          ),
    ]);
  }

  Future<void> _build(Future<SendPort?> port, List<Stroke> strokes) async {
    final worker = _closed ? null : await port;
    if (worker == null) {
      await const InlineOutlinePreparer().prepare(strokes);
      return;
    }
    final reply = ReceivePort();
    worker.send((TransferableTypedData.fromList([_pack(strokes)]), reply.sendPort));
    final answer = await reply.first;
    reply.close();
    if (answer is! (TransferableTypedData, Int32List)) {
      await const InlineOutlinePreparer().prepare(strokes);
      return;
    }
    final (data, ends) = answer;
    final commands = data.materialize().asFloat64List();
    var start = 0;
    for (var i = 0; i < strokes.length; i++) {
      final end = ends[i];
      if (!StrokeRenderer.hasPath(strokes[i])) {
        StrokeRenderer.adopt(
          strokes[i],
          OutlineCommands.toPath(Float64List.sublistView(commands, start, end)),
        );
      }
      start = end;
    }
  }

  /// Per stroke: tool, width, the style's five numbers, the point count,
  /// then x, y, pressure of each point.
  static Float64List _pack(List<Stroke> strokes) {
    var length = 0;
    for (final s in strokes) {
      length += 8 + 3 * s.points.length;
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
        ..[i++] = style.taperStart
        ..[i++] = style.taperEnd
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
        taperStart: data[i + 5],
        taperEnd: data[i + 6],
      );
      final n = data[i + 7].toInt();
      i += 8;
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
        final strokes = _unpack(packed.materialize().asFloat64List());
        final outlines = [for (final s in strokes) OutlineCommands.of(s)];
        final ends = Int32List(outlines.length);
        var total = 0;
        for (var k = 0; k < outlines.length; k++) {
          ends[k] = total += outlines[k].length;
        }
        final all = Float64List(total);
        var at = 0;
        for (final o in outlines) {
          all.setRange(at, at += o.length, o);
        }
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
