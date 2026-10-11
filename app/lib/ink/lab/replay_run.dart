import 'dart:ui';

import '../../data/app_database.dart';
import '../../data/stroke_repository.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../render/live_stroke.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'input_recording.dart';
import 'replay.dart';

/// The live stroke as one frame of a replay showed it.
class ReplayFrame {
  const ReplayFrame({
    required this.index,
    required this.t,
    required this.vsyncUs,
    required this.points,
    required this.newestEventUs,
    required this.build,
    required this.committed,
    required this.commitTime,
    this.viewScale = 1,
    this.viewOffset = Offset.zero,
  });

  final int index;

  /// The viewport (world → logical screen px) at this frame: recordings may
  /// pan and zoom between strokes.
  final double viewScale;
  final Offset viewOffset;

  /// World → logical screen px at this frame.
  Offset toScreen(double x, double y) => Offset(x, y) * viewScale + viewOffset;

  /// Recording time of the frame boundary (µs) and the engine's vsync.
  final int t, vsyncUs;

  /// Points of the live stroke at this frame (empty: not drawing).
  final List<StrokePoint> points;

  /// Newest pointer event handled before the frame (µs, event clock).
  final int newestEventUs;

  /// Time to build the live outline, as `LiveInkPainter` does each frame
  /// (incrementally, see `LiveStrokeBuilder`).
  final Duration build;

  /// Strokes committed since the previous frame, and the pen-up handling
  /// time that took (model commit included, outline not).
  final List<Stroke> committed;
  final Duration commitTime;

  bool get drawing => points.isNotEmpty;
}

/// A recording replayed frame by frame: the live stroke per frame, the
/// committed strokes and timings.
class ReplayResult {
  ReplayResult({
    required this.recording,
    required this.pen,
    required this.frames,
    required this.viewScale,
    required this.viewOffset,
    required this.style,
  });

  final InputRecording recording;
  final PenSettings pen;
  final List<ReplayFrame> frames;

  /// Viewport scale during the replay (world → logical screen px).
  final double viewScale;
  final Offset viewOffset;

  /// World → logical screen px, as the replay's viewport ended up.
  Offset toScreen(double x, double y) => Offset(x, y) * viewScale + viewOffset;

  /// The frame that committed [stroke] (the screen as it was drawn).
  ReplayFrame frameOf(Stroke stroke) =>
      (_commitFrames ??= Map.identity()
        ..addAll({
          for (final f in frames)
            for (final s in f.committed) s: f,
        }))[stroke] ??
      frames.last;
  Map<Stroke, ReplayFrame>? _commitFrames;

  /// World → logical screen px as the screen was when [stroke] was drawn.
  Offset Function(double, double) screenOf(Stroke stroke) => frameOf(stroke).toScreen;

  /// The style the replayed strokes get from [pen].
  final StrokeStyle style;

  List<Stroke> get strokes => [for (final f in frames) ...f.committed];

  /// Runs [recording] through the real pipeline with [pen] (default: the
  /// recorded pen) into an in-memory surface. Each frame's live outline is
  /// built (and timed) as `LiveInkPainter` builds it: incrementally.
  /// [timingRepeats] is accepted for compatibility (the incremental build
  /// cannot be repeated).
  static ReplayResult run(InputRecording recording, {PenSettings? pen, int timingRepeats = 1}) {
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 'inklab',
      repository: StrokeRepository(db, deviceId: 'inklab'),
    );
    final live = LiveInk();
    final viewport = ViewportController(minScale: 0.01, maxScale: 64);
    final driver = ReplayDriver(recording, model: model, live: live, viewport: viewport, pen: pen);
    final frames = <ReplayFrame>[];
    Duration timeBuild() {
      final watch = Stopwatch()..start();
      LiveStrokeBuilder.livePath(live);
      return watch.elapsed;
    }

    try {
      for (var step = driver.step(); step != null; step = driver.step()) {
        final points = live.isDrawing ? List<StrokePoint>.of(live.points) : const <StrokePoint>[];
        frames.add(
          ReplayFrame(
            index: frames.length,
            t: step.frame?.t ?? (recording.entries.isEmpty ? 0 : recording.entries.last.t),
            vsyncUs: step.frame?.vsyncUs ?? 0,
            points: points,
            newestEventUs: step.newestEventUs,
            build: points.isEmpty ? Duration.zero : timeBuild(),
            committed: step.committed,
            commitTime: step.commitTime,
            viewScale: viewport.scale,
            viewOffset: viewport.offset,
          ),
        );
      }
    } finally {
      model.dispose();
      live.dispose();
      viewport.dispose();
      db.close();
    }
    return ReplayResult(
      recording: recording,
      pen: driver.pen,
      frames: frames,
      viewScale: viewport.scale,
      viewOffset: viewport.offset,
      style: driver.tools.styleFor(driver.pen.tool),
    );
  }
}
