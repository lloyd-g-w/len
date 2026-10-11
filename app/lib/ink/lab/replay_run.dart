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
  });

  final int index;

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
  const ReplayResult({
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
    LiveStrokeBuilder? builder;
    Duration timeBuild(List<StrokePoint> points) {
      final watch = Stopwatch()..start();
      final built = LiveStrokeBuilder.build(
        builder,
        points,
        tool: live.tool,
        width: live.width,
        style: live.style,
      );
      final took = watch.elapsed;
      builder = built.builder;
      return took;
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
            build: points.isEmpty ? Duration.zero : timeBuild(points),
            committed: step.committed,
            commitTime: step.commitTime,
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
