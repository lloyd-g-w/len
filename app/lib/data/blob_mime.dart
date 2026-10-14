import 'dart:typed_data';

import '../domain/waveform.dart';

/// Tells a blob's MIME type by its content's signature, for blobs that
/// arrive without one (downloads from the sync server).
abstract final class BlobMime {
  /// Unrecognised content.
  static const String unknown = 'application/octet-stream';

  /// The MIME type of [bytes]: the kinds of blob Len stores (PDFs, images,
  /// recorded audio, waveforms), else [unknown].
  static String sniff(Uint8List bytes) {
    bool at(int offset, List<int> sig) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(0, '%PDF'.codeUnits)) return 'application/pdf';
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, 'GIF8'.codeUnits)) return 'image/gif';
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WAVE'.codeUnits)) return 'audio/wav';
    if (at(0, 'BM'.codeUnits)) return 'image/bmp';
    if (at(4, 'ftyp'.codeUnits) && bytes.length >= 12) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {'heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1'}.contains(brand)) {
        return 'image/heic';
      }
      if (brand == 'avif') return 'image/avif';
      return 'audio/mp4'; // Len's MP4s are recordings.
    }
    if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) return 'audio/webm';
    // ADTS (raw AAC): a 12-bit sync word, then MPEG-4, layer 0.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] & 0xF6 == 0xF0) return 'audio/aac';
    if (at(0, const [0x4C, 0x57, 1])) return Waveform.mime; // See [Waveform.encode].
    return unknown;
  }
}
