import 'dart:typed_data';

import 'ebml.dart';

/// Cuts WebM audio (Opus, as browsers record it) to a stretch of time
/// without decoding: the blocks (packets) overlapping it are kept, their
/// timestamps rebased to start at 0 and regrouped into clusters of known
/// size. The EBML header and the tracks are kept, the duration is
/// rewritten, the index (`Cues`) and `SeekHead` are dropped (they would
/// point at the wrong bytes). Opus packets are all keyframes, so the cut
/// is exact to a packet (20 ms).
///
/// Browsers write the segment and clusters with unknown sizes (live
/// streams); both are read.
abstract final class WebmCut {
  static const int _segment = 0x18538067,
      _seekHead = 0x114D9B74,
      _info = 0x1549A966,
      _tracks = 0x1654AE6B,
      _cluster = 0x1F43B675,
      _cues = 0x1C53BB6B,
      _tags = 0x1254C367,
      _chapters = 0x1043A770,
      _attachments = 0x1941A469,
      _void = 0xEC,
      _crc32 = 0xBF,
      _timecodeScale = 0x2AD7B1,
      _duration = 0x4489,
      _timecode = 0xE7,
      _simpleBlock = 0xA3,
      _blockGroup = 0xA0,
      _block = 0xA1,
      _blockDuration = 0x9B;

  /// Level-1 elements: they end a cluster of unknown size.
  static const Set<int> _topLevel = {
    _seekHead, _info, _tracks, _cluster, _cues, _tags, _chapters, _attachments, //
  };

  /// [bytes] cut to the blocks overlapping [fromMs]…[toMs] (ms from the
  /// first block; null leaves that end open), or null when [bytes] isn't
  /// WebM this can cut or nothing lies in the range.
  static Uint8List? cut(Uint8List bytes, {int? fromMs, int? toMs}) {
    try {
      return _cut(bytes, fromMs, toMs);
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Uint8List? _cut(Uint8List d, int? fromMs, int? toMs) {
    final header = Ebml.read(d, 0, d.length);
    if (header == null || header.id != 0x1A45DFA3 || header.unknown) return null;
    final segment = Ebml.read(d, header.end, d.length);
    if (segment == null || segment.id != _segment) return null;
    final kept = <Uint8List>[]; // Level-1 elements kept before the clusters.
    final blocks = <_Block>[];
    Uint8List? info;
    var scale = 1000000; // ns per timecode unit
    var clusters = 0;
    for (var pos = segment.dataStart; pos < segment.end;) {
      final e = Ebml.read(d, pos, segment.end);
      if (e == null) return null;
      if (e.id == _cluster) {
        final end = _readCluster(d, e, segment.end, clusters++, blocks);
        if (end == null) return null;
        pos = end;
        continue;
      }
      if (e.unknown) return null;
      pos = e.end;
      switch (e.id) {
        case _info:
          final children = Ebml.children(d, e.dataStart, e.end);
          if (children == null) return null;
          final parts = <Uint8List>[];
          for (final c in children) {
            if (c.id == _timecodeScale) scale = Ebml.uint(d, c) ?? 0;
            if (c.id != _duration && c.id != _void && c.id != _crc32) {
              parts.add(Uint8List.sublistView(d, c.start, c.end));
            }
          }
          info = _concat(parts);
        case _seekHead || _cues || _void || _crc32:
          break;
        default:
          kept.add(Uint8List.sublistView(d, e.start, e.end));
      }
    }
    if (info == null || blocks.isEmpty || scale <= 0) return null;

    double ms(int units) => units * scale / 1000000;
    final first = blocks.first.time;
    final keep = <_Block>[];
    int? keptEnd;
    for (final (i, b) in blocks.indexed) {
      final end = b.endTime(
        i + 1 < blocks.length ? blocks[i + 1] : null,
        i > 0 ? blocks[i - 1] : null,
      );
      if (fromMs != null && ms(end - first) <= fromMs) continue;
      if (toMs != null && ms(b.time - first) >= toMs) break;
      keep.add(b);
      keptEnd = end;
    }
    if (keep.isEmpty) return null;

    final base = keep.first.time;
    final segmentBody = <Uint8List>[
      Ebml.element(_info, [info, Ebml.floatElement(_duration, (keptEnd! - base).toDouble())]),
      ...kept,
      ..._clusters(d, keep, base),
    ];
    return _concat([
      Uint8List.sublistView(d, header.start, header.end),
      Ebml.element(_segment, segmentBody),
    ]);
  }

  /// Reads the blocks of [cluster] (number [index]) into [blocks]; returns
  /// where the cluster ends, or null when it doesn't parse.
  static int? _readCluster(
    Uint8List d,
    EbmlElement cluster,
    int segmentEnd,
    int index,
    List<_Block> blocks,
  ) {
    int? timecode;
    var pos = cluster.dataStart;
    final end = cluster.unknown ? segmentEnd : cluster.end;
    while (pos < end) {
      final e = Ebml.read(d, pos, end);
      if (e == null) return null;
      if (cluster.unknown && _topLevel.contains(e.id)) return pos;
      if (e.unknown) return null;
      pos = e.end;
      switch (e.id) {
        case _timecode:
          timecode = Ebml.uint(d, e);
          if (timecode == null) return null;
        case _simpleBlock:
          if (timecode == null) return null;
          final b = _Block.of(d, e, e.dataStart, e.end, timecode, index, null);
          if (b == null) return null;
          blocks.add(b);
        case _blockGroup:
          if (timecode == null) return null;
          final children = Ebml.children(d, e.dataStart, e.end);
          if (children == null) return null;
          EbmlElement? block;
          int? duration;
          for (final c in children) {
            if (c.id == _block) block = c;
            if (c.id == _blockDuration) duration = Ebml.uint(d, c);
          }
          if (block == null) return null;
          final b = _Block.of(d, e, block.dataStart, block.end, timecode, index, duration);
          if (b == null) return null;
          blocks.add(b);
      }
    }
    return end;
  }

  /// [blocks] (timestamps rebased by [base]) in clusters: a new one where
  /// the original cluster changes or a block's offset outgrows 16 bits.
  static List<Uint8List> _clusters(Uint8List d, List<_Block> blocks, int base) {
    final out = <Uint8List>[];
    var body = <Uint8List>[];
    var clusterTime = 0, cluster = -1;
    void flush() {
      if (body.isNotEmpty) out.add(Ebml.element(_cluster, body));
    }

    for (final b in blocks) {
      final time = b.time - base;
      if (b.cluster != cluster || time - clusterTime > 0x7FFF) {
        flush();
        cluster = b.cluster;
        clusterTime = time;
        body = [Ebml.uintElement(_timecode, time)];
      }
      final copy = Uint8List.fromList(Uint8List.sublistView(d, b.start, b.end));
      final relative = time - clusterTime;
      copy[b.timecodeAt - b.start] = relative >> 8;
      copy[b.timecodeAt - b.start + 1] = relative & 0xFF;
      body.add(copy);
    }
    flush();
    return out;
  }
}

/// A block of a WebM cluster: its element's bytes [start]…[end], where its
/// 16-bit relative timecode sits ([timecodeAt]), its absolute [time] (in
/// timecode units) and the cluster it was in.
class _Block {
  _Block(this.start, this.end, this.timecodeAt, this.time, this.cluster, this.duration);

  final int start, end, timecodeAt, time, cluster;
  final int? duration;

  /// The block in [element] whose header is at [from]…[to], in a cluster at
  /// [clusterTime]; null when malformed.
  static _Block? of(
    Uint8List d,
    EbmlElement element,
    int from,
    int to,
    int clusterTime,
    int cluster,
    int? duration,
  ) {
    // Track number (a variable-length integer), int16 timecode, flags.
    final first = d[from];
    var trackLength = 1;
    while (trackLength <= 8 && first & (0x100 >> trackLength) == 0) {
      trackLength++;
    }
    final at = from + trackLength;
    if (trackLength > 8 || at + 3 > to) return null;
    final relative = (d[at] << 8 | d[at + 1]).toSigned(16);
    return _Block(element.start, element.end, at, clusterTime + relative, cluster, duration);
  }

  /// Where this block's audio ends: its duration if it has one, else where
  /// [next] begins, else as long as the gap after [previous].
  int endTime(_Block? next, _Block? previous) {
    if (duration case final d?) return time + d;
    if (next != null) return next.time;
    return previous == null ? time : time + time - previous.time;
  }
}

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  parts.forEach(out.add);
  return out.takeBytes();
}
