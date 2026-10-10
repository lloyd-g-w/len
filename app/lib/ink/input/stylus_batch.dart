import 'dart:typed_data';

/// One digitiser sample of a stylus, as Android reported it.
class StylusSample {
  const StylusSample({
    required this.timeUs,
    required this.x,
    required this.y,
    required this.pressure,
    this.tilt = 0,
    this.orientation = 0,
  });

  /// Event time in microseconds, on the clock of Flutter's
  /// `PointerEvent.timeStamp` (Android uptime).
  final double timeUs;

  /// Position in physical pixels of the Flutter view.
  final double x, y;

  /// Raw pressure (in the device's own range, like `PointerEvent.pressure`).
  final double pressure;

  /// Radians from the screen normal (0 = upright), and the azimuth of the
  /// pen's lean (`AXIS_ORIENTATION`, radians).
  final double tilt, orientation;
}

/// The samples of one stylus pointer in one Android `MotionEvent`: the
/// historical samples the system batched since the previous event, then
/// the event's own (current) sample — the only one Flutter forwards.
class StylusBatch {
  const StylusBatch({
    required this.device,
    required this.downTimeUs,
    required this.eventTimeUs,
    required this.samples,
  });

  /// Flutter's `PointerEvent.device` for this pointer.
  final int device;

  /// When the contact began; equals the `timeStamp` of its down event.
  final double downTimeUs;

  /// The event's time; equals the `timeStamp` of the pointer event Flutter
  /// makes from it.
  final double eventTimeUs;

  /// Historical samples, oldest first, then the current one (last).
  final List<StylusSample> samples;

  /// Samples Flutter never sees (all but the last).
  Iterable<StylusSample> get historical => samples.take(samples.length - 1);
}

/// Binary format of the `len/stylus_samples` channel (little endian), as
/// written by `StylusCapture.kt`:
///
/// ```text
/// int32 version (1), int32 batch count, then per batch:
///   int32 device, int32 sample count, float64 down time µs, float64 event time µs,
///   per sample: float64 time µs, float32 x, y, pressure, tilt, orientation
/// ```
/// Times are float64 (exact for µs) because 64-bit integers are not
/// available in `ByteData` on the web.
abstract final class StylusBatchCodec {
  static const int version = 1;
  static const int _headerBytes = 8;
  static const int _batchBytes = 24;
  static const int _sampleBytes = 28;

  /// Decodes a message; malformed or unknown-version messages yield nothing.
  static List<StylusBatch> decode(ByteData data) {
    if (data.lengthInBytes < _headerBytes) return const [];
    if (data.getInt32(0, Endian.little) != version) return const [];
    final count = data.getInt32(4, Endian.little);
    final batches = <StylusBatch>[];
    var o = _headerBytes;
    for (var b = 0; b < count; b++) {
      if (o + _batchBytes > data.lengthInBytes) return const [];
      final device = data.getInt32(o, Endian.little);
      final n = data.getInt32(o + 4, Endian.little);
      final down = data.getFloat64(o + 8, Endian.little);
      final time = data.getFloat64(o + 16, Endian.little);
      o += _batchBytes;
      if (n < 1 || o + n * _sampleBytes > data.lengthInBytes) return const [];
      final samples = <StylusSample>[];
      for (var i = 0; i < n; i++, o += _sampleBytes) {
        samples.add(
          StylusSample(
            timeUs: data.getFloat64(o, Endian.little),
            x: data.getFloat32(o + 8, Endian.little),
            y: data.getFloat32(o + 12, Endian.little),
            pressure: data.getFloat32(o + 16, Endian.little),
            tilt: data.getFloat32(o + 20, Endian.little),
            orientation: data.getFloat32(o + 24, Endian.little),
          ),
        );
      }
      batches.add(
        StylusBatch(device: device, downTimeUs: down, eventTimeUs: time, samples: samples),
      );
    }
    return batches;
  }

  /// Encodes [batches] in the channel format (used by tests).
  static ByteData encode(List<StylusBatch> batches) {
    var size = _headerBytes;
    for (final b in batches) {
      size += _batchBytes + b.samples.length * _sampleBytes;
    }
    final data = ByteData(size)
      ..setInt32(0, version, Endian.little)
      ..setInt32(4, batches.length, Endian.little);
    var o = _headerBytes;
    for (final b in batches) {
      data
        ..setInt32(o, b.device, Endian.little)
        ..setInt32(o + 4, b.samples.length, Endian.little)
        ..setFloat64(o + 8, b.downTimeUs, Endian.little)
        ..setFloat64(o + 16, b.eventTimeUs, Endian.little);
      o += _batchBytes;
      for (final s in b.samples) {
        data
          ..setFloat64(o, s.timeUs, Endian.little)
          ..setFloat32(o + 8, s.x, Endian.little)
          ..setFloat32(o + 12, s.y, Endian.little)
          ..setFloat32(o + 16, s.pressure, Endian.little)
          ..setFloat32(o + 20, s.tilt, Endian.little)
          ..setFloat32(o + 24, s.orientation, Endian.little);
        o += _sampleBytes;
      }
    }
    return data;
  }
}
