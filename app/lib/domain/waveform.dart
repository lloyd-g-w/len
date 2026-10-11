import 'dart:math' as math;
import 'dart:typed_data';

/// The loudness outline of a recording, for the playback scrubber: one
/// level (0…255) per [bucketMs] of audio, captured while recording (from
/// the recorder's input level, so no audio ever has to be decoded) and
/// stored as a small blob next to the audio (≈ 36 KB per hour).
///
/// Format (`application/x-len-waveform`): the bytes `L` `W`, a version
/// byte (1), the bucket length in units of 10 ms, then one byte per bucket.
class Waveform {
  Waveform(this.levels, {this.bucketMs = defaultBucketMs})
    : assert(bucketMs > 0 && bucketMs % 10 == 0 && bucketMs <= 2550);

  static const int defaultBucketMs = 100;
  static const String mime = 'application/x-len-waveform';
  static const int _version = 1;

  /// One level per bucket, 0 (silence) … 255 (loudest).
  final Uint8List levels;
  final int bucketMs;

  int get durationMs => levels.length * bucketMs;

  Uint8List encode() {
    final out = Uint8List(4 + levels.length)
      ..[0] = 0x4C
      ..[1] = 0x57
      ..[2] = _version
      ..[3] = bucketMs ~/ 10;
    out.setRange(4, out.length, levels);
    return out;
  }

  /// Parses [encode]'s output; null when it is not a waveform.
  static Waveform? decode(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x4C || bytes[1] != 0x57 || bytes[2] != _version) {
      return null;
    }
    if (bytes[3] == 0) return null;
    return Waveform(Uint8List.fromList(bytes.sublist(4)), bucketMs: bytes[3] * 10);
  }

  /// [count] bars (0…1) over [durationMs] of audio (the recording's
  /// length; buckets beyond the waveform are silent): each bar is the
  /// loudest bucket it covers.
  List<double> bars(int count, {required int durationMs}) {
    if (count <= 0) return const [];
    final total = math.max(1, durationMs);
    return List.generate(count, (i) {
      final from = (i * total / count / bucketMs).floor();
      final to = math.max(from + 1, ((i + 1) * total / count / bucketMs).ceil());
      var peak = 0;
      for (var b = from; b < to && b < levels.length; b++) {
        if (levels[b] > peak) peak = levels[b];
      }
      return peak / 255;
    });
  }
}

/// Collects input levels during a recording into a [Waveform].
class WaveformBuilder {
  WaveformBuilder({this.bucketMs = Waveform.defaultBucketMs});

  final int bucketMs;
  final List<int> _levels = [];

  /// Notes [level] (0…1) heard at audio position [positionMs]; a bucket
  /// keeps its loudest level.
  void add(int positionMs, double level) {
    if (positionMs < 0) return;
    final index = positionMs ~/ bucketMs;
    final value = (level.clamp(0.0, 1.0) * 255).round();
    while (_levels.length <= index) {
      _levels.add(-1);
    }
    if (value > _levels[index]) _levels[index] = value;
  }

  /// The waveform of [durationMs] of audio. Buckets no level arrived for
  /// (level events are not exactly periodic) take the previous level.
  Waveform build(int durationMs) {
    final count = (durationMs / bucketMs).ceil();
    final out = Uint8List(math.max(0, count));
    var last = 0;
    for (var i = 0; i < out.length; i++) {
      final v = i < _levels.length ? _levels[i] : -1;
      if (v >= 0) last = v;
      out[i] = v >= 0 ? v : last;
    }
    return Waveform(out, bucketMs: bucketMs);
  }

  void clear() => _levels.clear();
}
