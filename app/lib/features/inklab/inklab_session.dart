import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/app_database.dart';
import '../../data/stroke_repository.dart';
import '../../ink/input/ink_input_controller.dart';
import '../../ink/input/live_ink.dart';
import '../../ink/input/wet_ink.dart';
import '../../ink/lab/input_recorder.dart';
import '../../ink/lab/input_recording.dart';
import '../../ink/lab/lab_stats.dart';
import '../../ink/lab/replay.dart';
import '../../ink/surface_model.dart';
import '../../ink/tool_settings.dart';
import '../../ink/viewport.dart';
import '../../platform/sqlite_connection.dart';
import '../../platform/stylus_samples.dart';

/// Everything the Ink Lab draws into and records: a scratch surface in a
/// private in-memory database (nothing reaches the user's notebooks or
/// sync), the real input pipeline and an [InputRecorder] with live
/// [LabStats].
///
/// Notifies listeners when the surface is replaced ([clear]) or the pen
/// changes.
class InkLabSession extends ChangeNotifier {
  InkLabSession._(this._db, {required this.stylusOnly})
    : _strokes = StrokeRepository(_db, deviceId: 'inklab') {
    model = _newModel();
    tools = ToolSettings(stylusOnly: stylusOnly)..holdToStraighten = false;
    ReplayDriver.applyPen(tools, _pen);
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      samples: openStylusSamples(
        wetInk: () => WetInkStyle.of(live, viewport.scale),
        wetInkNext: () => WetInkStyle.forNextStroke(tools, viewport.scale),
        wetInkView: () => WetInkView.of(viewport),
      ),
    );
    recorder.onEntry = (e) => stats.add(e);
  }

  /// Opens a session on a fresh in-memory database.
  static Future<InkLabSession> open({bool stylusOnly = false}) async => InkLabSession._(
    AppDatabase.fromConnection(await openSqliteScratch()),
    stylusOnly: stylusOnly,
  );

  final AppDatabase _db;
  final StrokeRepository _strokes;

  /// Palm rejection: only the stylus draws, fingers navigate.
  final bool stylusOnly;

  /// The scratch surface (replaced by [clear]).
  late SurfaceModel model;
  final LiveInk live = LiveInk();
  final ViewportController viewport = ViewportController(minScale: 0.05, maxScale: 16);
  late final ToolSettings tools;
  late final InkInputController input;
  final InputRecorder recorder = InputRecorder(
    meta: const RecordingMeta(devicePixelRatio: 1, viewSize: Size.zero, pen: PenSettings()),
  );

  /// Statistics since the last [clear] (replaced by [resetStats]).
  LabStats stats = LabStats();

  /// Surface size (logical px) and device pixel ratio, set by the screen.
  Size viewSize = Size.zero;
  double devicePixelRatio = 1;

  int _surfaces = 0;
  PenSettings _pen = const PenSettings();
  bool _recording = false;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  int _startedAtMs = DateTime.now().millisecondsSinceEpoch;

  /// The pen new strokes are drawn with.
  PenSettings get pen => _pen;
  set pen(PenSettings value) {
    _pen = value;
    ReplayDriver.applyPen(tools, value);
    notifyListeners();
  }

  /// Strokes on the surface.
  int get strokeCount => model.loadedStrokeCount;

  SurfaceModel _newModel() =>
      SurfaceModel(surfaceId: 'inklab-${_surfaces++}', repository: _strokes);

  /// Starts recording stylus batches and frame boundaries (pointer events
  /// come from the screen's `Listener`).
  void startRecording() {
    if (_recording) return;
    _recording = true;
    observeStylusBatches(recorder.addBatches);
    recorder.attachToScheduler();
  }

  /// Stops receiving batches and frames (e.g. while replaying).
  void stopRecording() {
    if (!_recording) return;
    _recording = false;
    observeStylusBatches(null);
    recorder.detach();
  }

  /// Whether pointer events should be recorded.
  bool get recording => _recording;

  /// What was recorded since the last [clear], with its settings.
  InputRecording get recordingSoFar => (recorder..meta = meta()).recording;

  /// The settings stored with a recording started now (or at the last
  /// [clear]).
  RecordingMeta meta() => RecordingMeta(
    createdAtMs: _startedAtMs,
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    devicePixelRatio: devicePixelRatio,
    viewSize: viewSize,
    viewScale: _startScale,
    viewOffset: _startOffset,
    pen: _pen,
    stylusOnly: stylusOnly,
  );

  /// Empties the surface, the recording and the statistics, and resets
  /// the view.
  void clear() {
    final old = model;
    _strokes.deleteSurfaces([old.surfaceId]);
    model = _newModel();
    input.model = model;
    old.dispose();
    viewport.setView(scale: 1, offset: Offset.zero);
    _startScale = viewport.scale;
    _startOffset = viewport.offset;
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;
    recorder.clear();
    resetStats();
    notifyListeners();
  }

  /// Starts fresh statistics.
  void resetStats() => stats = LabStats();

  @override
  void dispose() {
    stopRecording();
    model.dispose();
    tools.dispose();
    live.dispose();
    viewport.dispose();
    _db.close();
    super.dispose();
  }
}
