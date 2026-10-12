import 'dart:typed_data';

/// Reads raw AAC in ADTS frames (`audio/aac`, the format Len records in
/// natively): every frame starts with a 7- or 9-byte header holding its
/// length and sample rate, so a stream can be cut between any two frames,
/// files can be joined by concatenation, and a file cut off mid-frame (the
/// app was killed while recording) is playable up to its last whole frame.
///
/// Feed bytes in any chunks with [add]; it returns the whole frames among
/// them and counts their audio. Bytes that are not a frame are skipped
/// until the next frame header.
class AdtsReader {
  /// Samples per AAC raw data block.
  static const int samplesPerBlock = 1024;

  /// Sample rates by an ADTS header's sampling frequency index.
  static const List<int> sampleRates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350, //
  ];

  Uint8List _pending = Uint8List(0);

  /// Whole frames read so far.
  int frames = 0;

  /// Audio read so far, in µs (exact sums across sample rates).
  int _micros = 0;

  /// Audio in the whole frames read so far.
  int get durationMs => _micros ~/ 1000;

  /// Bytes held back: the start of a frame not complete yet.
  int get pendingBytes => _pending.length;

  /// Adds [bytes]; returns the whole frames completed by them (possibly
  /// none), concatenated.
  Uint8List add(List<int> bytes) {
    final data = _pending.isEmpty
        ? (bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
        : (BytesBuilder(copy: false)
                ..add(_pending)
                ..add(bytes))
              .takeBytes();
    final out = BytesBuilder(copy: false);
    var i = 0;
    var runStart = 0;
    while (i + 7 <= data.length) {
      final length = _frameLength(data, i);
      if (length == null) {
        if (i > runStart) out.add(Uint8List.sublistView(data, runStart, i));
        i++;
        runStart = i;
        continue;
      }
      if (i + length > data.length) break;
      _count(data, i);
      i += length;
    }
    if (i > runStart) out.add(Uint8List.sublistView(data, runStart, i));
    _pending = Uint8List.fromList(Uint8List.sublistView(data, i));
    return out.takeBytes();
  }

  /// The length of the frame whose header starts at [i], or null when no
  /// valid header does.
  static int? _frameLength(Uint8List d, int i) {
    // Sync word 0xFFF, MPEG layer 0.
    if (d[i] != 0xFF || (d[i + 1] & 0xF6) != 0xF0) return null;
    if (((d[i + 2] >> 2) & 0x0F) >= sampleRates.length) return null;
    final length = ((d[i + 3] & 0x03) << 11) | (d[i + 4] << 3) | (d[i + 5] >> 5);
    final header = (d[i + 1] & 0x01) == 1 ? 7 : 9;
    return length > header ? length : null;
  }

  void _count(Uint8List d, int i) {
    final rate = sampleRates[(d[i + 2] >> 2) & 0x0F];
    final blocks = (d[i + 6] & 0x03) + 1;
    frames++;
    _micros += blocks * samplesPerBlock * 1000000 ~/ rate;
  }

  /// The whole frames of [bytes] and their duration: a file cut off
  /// mid-frame loses only its partial last frame.
  static ({Uint8List frames, int durationMs}) readAll(Uint8List bytes) {
    final reader = AdtsReader();
    final frames = reader.add(bytes);
    return (frames: frames, durationMs: reader.durationMs);
  }

  /// The duration of the ADTS audio in [chunks] (e.g. a file being read).
  static Future<int> measure(Stream<List<int>> chunks) async {
    final reader = AdtsReader();
    await for (final chunk in chunks) {
      reader.add(chunk);
    }
    return reader.durationMs;
  }
}
