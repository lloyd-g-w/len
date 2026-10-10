import 'dart:ui';

import '../../domain/stroke.dart';
import '../input/stylus_batch.dart';

/// A recording of exactly what the drawing surface received while the user
/// wrote in the Ink Lab: every pointer event, every batch of historical
/// stylus samples from the platform channel and every frame boundary, in
/// the order the app saw them, plus the settings needed to replay it.
///
/// Stored as a `.leninput` file ([RecordingCodec]); see `docs/INK_LAB.md`.
class InputRecording {
  const InputRecording({required this.meta, required this.entries});

  final RecordingMeta meta;

  /// Everything the app received, in arrival order.
  final List<InputEntry> entries;

  Iterable<PointerEntry> get pointers => entries.whereType<PointerEntry>();
  Iterable<BatchEntry> get batches => entries.whereType<BatchEntry>();
  Iterable<FrameEntry> get frames => entries.whereType<FrameEntry>();

  /// Strokes the recording's contacts should produce (stylus/touch/mouse
  /// downs), a rough count for summaries.
  int get contactCount => pointers.where((p) => p.type == PointerType.down).length;
}

/// The pen and view the recording was made with.
class RecordingMeta {
  const RecordingMeta({
    this.createdAtMs = 0,
    this.platform = 'unknown',
    this.note = '',
    required this.devicePixelRatio,
    required this.viewSize,
    this.viewScale = 1,
    this.viewOffset = Offset.zero,
    required this.pen,
    this.lowLatency = false,
    this.stylusOnly = true,
  });

  final int createdAtMs;

  /// `android`, `linux`, `web`, … or `sim` for simulated recordings.
  final String platform;

  /// Free text (what was written, which device, …).
  final String note;

  /// Physical pixels per logical pixel; stylus batches are in physical px.
  final double devicePixelRatio;

  /// Size of the drawing surface in logical pixels.
  final Size viewSize;

  /// The viewport at the start (`screen = world × scale + offset`).
  final double viewScale;
  final Offset viewOffset;

  final PenSettings pen;

  /// Whether the experimental low-latency overlay was on.
  final bool lowLatency;

  /// Palm rejection (stylus only).
  final bool stylusOnly;

  RecordingMeta copyWith({PenSettings? pen, String? note}) => RecordingMeta(
    createdAtMs: createdAtMs,
    platform: platform,
    note: note ?? this.note,
    devicePixelRatio: devicePixelRatio,
    viewSize: viewSize,
    viewScale: viewScale,
    viewOffset: viewOffset,
    pen: pen ?? this.pen,
    lowLatency: lowLatency,
    stylusOnly: stylusOnly,
  );
}

/// The ink a recording was drawn with.
class PenSettings {
  const PenSettings({
    this.tool = InkTool.ballpoint,
    this.color = 0xFF1A2233,
    this.width = 2.5,
    this.opacity = 1,
    this.thinning = 0.25,
    this.streamline = 0.4,
    this.taper = false,
  });

  final InkTool tool;
  final int color;
  final double width;
  final double opacity;
  final double thinning;

  /// Stabiliser (0..1).
  final double streamline;
  final bool taper;

  PenSettings copyWith({double? streamline, double? width, double? thinning, bool? taper}) =>
      PenSettings(
        tool: tool,
        color: color,
        width: width ?? this.width,
        opacity: opacity,
        thinning: thinning ?? this.thinning,
        streamline: streamline ?? this.streamline,
        taper: taper ?? this.taper,
      );
}

/// One thing the app received. [t] is when (µs since the recording
/// started, on the recorder's own monotonic clock).
sealed class InputEntry {
  const InputEntry(this.t);
  final int t;
}

/// The pointer event kinds that matter for drawing.
enum PointerType { down, move, up, cancel, hover }

/// A Flutter pointer event as the drawing surface's `Listener` saw it.
class PointerEntry extends InputEntry {
  const PointerEntry(
    super.t, {
    required this.type,
    required this.kind,
    required this.pointer,
    required this.device,
    required this.timeStampUs,
    required this.position,
    required this.localPosition,
    this.pressure = 0,
    this.pressureMin = 0,
    this.pressureMax = 1,
    this.buttons = 0,
    this.synthesized = false,
    this.tilt = 0,
    this.orientation = 0,
  });

  final PointerType type;
  final PointerDeviceKind kind;
  final int pointer;
  final int device;

  /// `PointerEvent.timeStamp` (on Android: the `MotionEvent`'s event time).
  final int timeStampUs;

  /// Global (view) and surface-local logical position.
  final Offset position;
  final Offset localPosition;
  final double pressure, pressureMin, pressureMax;
  final int buttons;
  final bool synthesized;
  final double tilt, orientation;
}

/// One `len/stylus_samples` channel message, decoded.
class BatchEntry extends InputEntry {
  const BatchEntry(super.t, this.batches);
  final List<StylusBatch> batches;
}

/// A frame began (persistent frame callback): everything received before
/// it is what that frame could show.
class FrameEntry extends InputEntry {
  const FrameEntry(super.t, {required this.vsyncUs});

  /// The engine's frame time stamp (vsync), raw.
  final int vsyncUs;
}

/// `FrameTiming` reported by the engine for a finished frame.
class TimingEntry extends InputEntry {
  const TimingEntry(
    super.t, {
    required this.frameNumber,
    required this.vsyncStartUs,
    required this.buildUs,
    required this.rasterUs,
    required this.totalUs,
  });

  final int frameNumber;
  final int vsyncStartUs;

  /// Build (UI thread) and raster durations, and vsync → raster end.
  final int buildUs, rasterUs, totalUs;
}
