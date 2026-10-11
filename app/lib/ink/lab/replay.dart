import 'package:flutter/gestures.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/ink_input_controller.dart';
import '../input/live_ink.dart';
import '../input/sample_source.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'input_recording.dart';
import 'replay_events.dart';

/// A clock that tells the recording's time and hands out predictable ids.
class ReplayClock extends Clock {
  ReplayClock(this.startMs);

  final int startMs;

  /// Recording time of the entry being replayed (µs).
  int nowUs = 0;
  int _ids = 0;

  @override
  int nowMs() => startMs + nowUs ~/ 1000;

  @override
  String newId() => 'replay-${_ids++}';

  /// The id [newId] handed out last, if any.
  String? get lastId => _ids == 0 ? null : 'replay-${_ids - 1}';
}

/// What happened between two frames of a replay.
class ReplayStep {
  const ReplayStep({
    required this.frame,
    required this.pointerEvents,
    required this.newestEventUs,
    required this.committed,
    required this.commitTime,
  });

  /// The frame boundary the step ended at; null for input after the last.
  final FrameEntry? frame;

  /// Pointer events handled in this step.
  final int pointerEvents;

  /// `timeStamp` of the newest pointer event handled so far (µs), what the
  /// low-latency overlay's `progress` reports.
  final int newestEventUs;

  /// Strokes committed during this step (pen-ups).
  final List<Stroke> committed;

  /// Time spent handling the pen-up events that committed them.
  final Duration commitTime;
}

/// Feeds a recording through the real input pipeline — [InkInputController]
/// with the platform's [StylusSampleMerger], [LiveInk] and the
/// [SurfaceModel] commit path — one recorded frame at a time.
///
/// The caller owns [model], [live] and [viewport] (the Ink Lab replays into
/// its visible surface; tests into in-memory ones) and paints or measures
/// between [step]s. Hold-to-straighten is off: it needs real timers.
class ReplayDriver {
  ReplayDriver(
    this.recording, {
    required SurfaceModel model,
    required this.live,
    required this.viewport,
    PenSettings? pen,
  }) : pen = pen ?? recording.meta.pen,
       clock = ReplayClock(recording.meta.createdAtMs) {
    final meta = recording.meta;
    viewport
      ..setSize(meta.viewSize)
      ..setView(scale: meta.viewScale, offset: meta.viewOffset);
    tools = ToolSettings(stylusOnly: meta.stylusOnly)..holdToStraighten = false;
    applyPen(tools, this.pen);
    controller = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      clock: clock,
      samples: StylusSampleMerger(_buffer, devicePixelRatio: () => meta.devicePixelRatio),
    );
  }

  final InputRecording recording;
  final LiveInk live;
  final ViewportController viewport;

  /// The pen the recording is replayed with (the recorded one by default).
  final PenSettings pen;
  final ReplayClock clock;
  late final ToolSettings tools;
  late final InkInputController controller;

  final StylusBatchBuffer _buffer = StylusBatchBuffer(capacity: 1 << 16);
  int _next = 0;
  int _newestEventUs = 0;

  bool get done => _next >= recording.entries.length;

  /// Handles the entries up to and including the next frame boundary.
  /// Returns null once everything was replayed.
  ReplayStep? step() {
    if (done) return null;
    var events = 0;
    final committed = <Stroke>[];
    var commitTime = Duration.zero;
    while (!done) {
      final entry = recording.entries[_next++];
      clock.nowUs = entry.t;
      switch (entry) {
        case FrameEntry():
          return ReplayStep(
            frame: entry,
            pointerEvents: events,
            newestEventUs: _newestEventUs,
            committed: committed,
            commitTime: commitTime,
          );
        case BatchEntry():
          _buffer.addAll(entry.batches);
        case PointerEntry():
          events++;
          if (entry.type != PointerType.hover) _newestEventUs = entry.timeStampUs;
          if (entry.type == PointerType.up) {
            final before = clock.lastId;
            final watch = Stopwatch()..start();
            _dispatch(entry);
            final id = clock.lastId;
            final stroke = id == before || id == null ? null : controller.model.strokeById(id);
            commitTime += watch.elapsed;
            if (stroke != null) committed.add(stroke);
          } else {
            _dispatch(entry);
          }
        case TimingEntry():
          break;
      }
    }
    return ReplayStep(
      frame: null,
      pointerEvents: events,
      newestEventUs: _newestEventUs,
      committed: committed,
      commitTime: commitTime,
    );
  }

  void _dispatch(PointerEntry entry) {
    final c = controller;
    switch (pointerEventOf(entry)) {
      case final PointerDownEvent e:
        c.handleDown(e);
      case final PointerMoveEvent e:
        c.handleMove(e);
      case final PointerUpEvent e:
        c.handleUp(e);
      case final PointerCancelEvent e:
        c.handleCancel(e);
      case final PointerHoverEvent e:
        c.handleHover(e);
      default:
        break;
    }
  }

  /// Configures [tools] to draw with [pen] (one colour and width slot).
  static void applyPen(ToolSettings tools, PenSettings pen) {
    tools.tool = pen.tool.isHighlighter ? EditorTool.highlighter : EditorTool.pen;
    tools.updateConfig(
      pen.tool,
      (c) => c.copyWith(
        colors: [pen.color | 0xFF000000],
        widths: [pen.width],
        colorIndex: 0,
        widthIndex: 0,
        opacity: pen.opacity,
        thinning: pen.thinning,
        streamline: pen.streamline,
        taper: pen.taper,
      ),
    );
  }
}
