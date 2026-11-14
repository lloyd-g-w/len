import 'dart:io';
import 'dart:typed_data';

import 'package:len/features/audio/ebml.dart';

/// Test helpers that read and write WebM and fragmented MP4 audio.

// --- WebM ---------------------------------------------------------------

/// An EBML element; [unknown] writes an unknown size (as browsers do).
Uint8List ebml(int id, List<Uint8List> body, {bool unknown = false}) {
  if (!unknown) return Ebml.element(id, body);
  final idBytes = Ebml.element(id, const []);
  final out = BytesBuilder()
    ..add(idBytes.sublist(0, idBytes.length - 1))
    ..add([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
  body.forEach(out.add);
  return out.takeBytes();
}

/// A SimpleBlock of track 1 at [relative] (to its cluster) holding [payload].
Uint8List simpleBlock(int relative, List<int> payload) => Ebml.element(0xA3, [
  Uint8List.fromList([0x81, (relative >> 8) & 0xFF, relative & 0xFF, 0x80, ...payload]),
]);

/// What a WebM file holds: its Info duration, its clusters' timecodes,
/// its blocks' absolute times and payloads, and which level-1 elements.
typedef WebmContents = ({
  double? duration,
  List<int> clusters,
  List<int> times,
  List<List<int>> payloads,
  List<int> topLevel,
});

/// Reads a WebM file of known sizes (as the cutter writes them).
WebmContents readWebm(Uint8List d) {
  final segment = Ebml.read(d, Ebml.read(d, 0, d.length)!.end, d.length)!;
  double? duration;
  final clusters = <int>[], times = <int>[], top = <int>[];
  final payloads = <List<int>>[];
  for (final e in Ebml.children(d, segment.dataStart, segment.end)!) {
    top.add(e.id);
    if (e.id == 0x1549A966) {
      for (final c in Ebml.children(d, e.dataStart, e.end)!) {
        if (c.id == 0x4489) {
          duration = ByteData.sublistView(d, c.dataStart, c.end).getFloat64(0);
        }
      }
    }
    if (e.id != 0x1F43B675) continue;
    var timecode = 0;
    for (final c in Ebml.children(d, e.dataStart, e.end)!) {
      if (c.id == 0xE7) {
        timecode = Ebml.uint(d, c)!;
        clusters.add(timecode);
      }
      var block = c;
      if (c.id == 0xA0) {
        block = Ebml.children(d, c.dataStart, c.end)!.firstWhere((b) => b.id == 0xA1);
      } else if (c.id != 0xA3) {
        continue;
      }
      final at = block.dataStart + 1;
      times.add(timecode + (d[at] << 8 | d[at + 1]).toSigned(16));
      payloads.add(d.sublist(at + 3, block.end));
    }
  }
  return (duration: duration, clusters: clusters, times: times, payloads: payloads, topLevel: top);
}

// --- MP4 ----------------------------------------------------------------

Uint8List box(String type, List<Uint8List> body) {
  final size = 8 + body.fold<int>(0, (sum, b) => sum + b.length);
  final out = BytesBuilder()
    ..add(_u32(size))
    ..add(type.codeUnits);
  body.forEach(out.add);
  return out.takeBytes();
}

/// A full box whose body is the 32-bit [words].
Uint8List fullBox(String type, int version, int flags, List<int> words) =>
    box(type, [_u32(version << 24 | flags), for (final w in words) _u32(w)]);

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// The boxes of [d] between [from] and [to]: (type, start, end).
List<(String, int, int)> boxes(Uint8List d, [int from = 0, int? to]) {
  final data = ByteData.sublistView(d);
  final out = <(String, int, int)>[];
  for (var p = from; p < (to ?? d.length);) {
    final size = data.getUint32(p);
    out.add((String.fromCharCodes(d.sublist(p + 4, p + 8)), p, p + size));
    p += size;
  }
  return out;
}

/// The samples of a fragmented MP4 written by the cutter (explicit sample
/// tables): decode times and payloads, and its top-level box types.
({List<int> times, List<List<int>> payloads, List<String> top}) readMp4(Uint8List d) {
  final data = ByteData.sublistView(d);
  final times = <int>[];
  final payloads = <List<int>>[];
  final top = boxes(d);
  for (final (type, start, end) in top) {
    if (type != 'moof') continue;
    final traf = boxes(d, start + 8, end).firstWhere((b) => b.$1 == 'traf');
    var time = 0;
    for (final (t, s, _) in boxes(d, traf.$2 + 8, traf.$3)) {
      if (t == 'tfdt') time = data.getUint32(s + 12) * 0x100000000 + data.getUint32(s + 16);
      if (t != 'trun') continue;
      final flags = data.getUint32(s + 8) & 0xFFFFFF;
      final count = data.getUint32(s + 12);
      var offset = start + data.getInt32(s + 16);
      var p = s + 20;
      for (var i = 0; i < count; i++) {
        final duration = data.getUint32(p), size = data.getUint32(p + 4);
        p += flags & 0x800 != 0 ? 16 : 12;
        times.add(time);
        payloads.add(d.sublist(offset, offset + size));
        time += duration;
        offset += size;
      }
    }
  }
  return (times: times, payloads: payloads, top: [for (final b in top) b.$1]);
}

// --- ffmpeg -------------------------------------------------------------

/// The first packet's time and the end of the last (s) that ffprobe reads
/// from [bytes] (written to a file named [name]) after ffmpeg decoded it
/// without complaint, or null when ffmpeg isn't installed.
Future<(double, double)?> probe(Uint8List bytes, String name) async {
  final dir = await Directory.systemTemp.createTemp('len_audio');
  try {
    final path = '${dir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    final ProcessResult decoded, packets;
    try {
      decoded = await Process.run('ffmpeg', ['-v', 'error', '-i', path, '-f', 'null', '-']);
      packets = await Process.run('ffprobe', [
        '-v', 'error', '-show_entries', 'packet=pts_time,duration_time', '-of', 'csv=p=0', path, //
      ]);
    } on ProcessException {
      return null;
    }
    for (final r in [decoded, packets]) {
      if (r.exitCode != 0 || (r.stderr as String).trim().isNotEmpty) {
        throw StateError('ffmpeg: ${r.stderr}');
      }
    }
    final times = [
      for (final l in (packets.stdout as String).trim().split('\n'))
        if (l.contains(',')) l.split(',').take(2).map(double.parse).toList(),
    ];
    return (times.first[0], times.last[0] + times.last[1]);
  } finally {
    dir.deleteSync(recursive: true);
  }
}
