import 'dart:math';
import 'dart:typed_data';

/// Cuts fragmented MP4 audio (AAC, as browsers record it: `ftyp`, `moov`,
/// then `moof` + `mdat` fragments) to a stretch of time without decoding:
/// the samples overlapping it are kept, each fragment rewritten with
/// explicit sample tables and its decode time (`tfdt`) rebased to start
/// at 0; `ftyp` and `moov` are kept (durations rewritten), indexes
/// (`sidx`, `mfra`) dropped. AAC frames are all sync samples, so the cut
/// is exact to a frame (≈ 21–23 ms). One track only; anything else (plain
/// MP4, several tracks, encryption, sample groups) returns null.
abstract final class Mp4Cut {
  /// [bytes] cut to the samples overlapping [fromMs]…[toMs] (ms from the
  /// first sample; null leaves that end open), or null when [bytes] isn't
  /// fragmented MP4 this can cut or nothing lies in the range.
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
    final data = ByteData.sublistView(d);
    Uint8List? ftyp;
    _Movie? movie;
    final samples = <_Sample>[];
    var fragments = 0;
    for (final box in _boxes(data, 0, d.length)) {
      switch (box.type) {
        case 'ftyp':
          ftyp = Uint8List.sublistView(d, box.start, box.end);
        case 'moov':
          movie = _Movie.read(data, box);
          if (movie == null) return null;
        case 'moof':
          if (movie == null) return null;
          final next = samples.isEmpty ? 0 : samples.last.time + samples.last.duration;
          if (!_readFragment(data, box, movie, fragments++, next, samples)) return null;
      }
    }
    if (movie == null || samples.isEmpty) return null;

    final ts = movie.timescale;
    final first = samples.first.time;
    double ms(int t) => (t - first) * 1000 / ts;
    final keep = [
      for (final s in samples)
        if ((fromMs == null || ms(s.time + s.duration) > fromMs) &&
            (toMs == null || ms(s.time) < toMs))
          s,
    ];
    if (keep.isEmpty) return null;
    final base = keep.first.time;
    final duration = keep.last.time + keep.last.duration - base;

    final out = BytesBuilder(copy: false);
    if (ftyp != null) out.add(ftyp);
    out.add(movie.withDuration(d, duration));
    var sequence = 1;
    for (var i = 0; i < keep.length;) {
      var j = i;
      while (j < keep.length && keep[j].fragment == keep[i].fragment) {
        j++;
      }
      out.add(_fragment(d, movie, keep.sublist(i, j), sequence++, base));
      i = j;
    }
    return out.takeBytes();
  }

  /// Reads the samples of the fragment [moof] (number [index]; decode time
  /// [next] when it has no `tfdt`) into [samples]; false when unsupported.
  static bool _readFragment(
    ByteData data,
    _Box moof,
    _Movie movie,
    int index,
    int next,
    List<_Sample> samples,
  ) {
    final trafs = [
      for (final b in _boxes(data, moof.dataStart, moof.end))
        if (b.type == 'traf') b,
    ];
    if (trafs.length != 1) return false;
    var time = next;
    var defaults = movie.defaults;
    var base = moof.start;
    int? dataEnd;
    for (final box in _boxes(data, trafs.single.dataStart, trafs.single.end)) {
      final flags = data.getUint32(box.dataStart) & 0xFFFFFF;
      final version = data.getUint8(box.dataStart);
      var p = box.dataStart + 4;
      switch (box.type) {
        case 'tfhd':
          if (data.getUint32(p) != movie.trackId) return false;
          p += 4;
          if (flags & 0x01 != 0) (base, p) = (_u64(data, p), p + 8);
          if (flags & 0x02 != 0) p += 4;
          int field(int bit, int fallback) {
            if (flags & bit == 0) return fallback;
            p += 4;
            return data.getUint32(p - 4);
          }

          defaults = (
            duration: field(0x08, defaults.duration),
            size: field(0x10, defaults.size),
            flags: field(0x20, defaults.flags),
          );
        case 'tfdt':
          time = version == 1 ? _u64(data, p) : data.getUint32(p);
        case 'trun':
          final count = data.getUint32(p);
          p += 4;
          var offset = dataEnd ?? base;
          if (flags & 0x01 != 0) (offset, p) = (base + data.getInt32(p), p + 4);
          int? firstFlags;
          if (flags & 0x04 != 0) (firstFlags, p) = (data.getUint32(p), p + 4);
          for (var i = 0; i < count; i++) {
            int field(int bit, int fallback) {
              if (flags & bit == 0) return fallback;
              p += 4;
              return data.getUint32(p - 4);
            }

            final duration = field(0x100, defaults.duration);
            final size = field(0x200, defaults.size);
            final sampleFlags = field(
              0x400,
              i == 0 ? firstFlags ?? defaults.flags : defaults.flags,
            );
            var cto = 0;
            if (flags & 0x800 != 0) {
              cto = version == 0 ? data.getUint32(p) : data.getInt32(p);
              p += 4;
            }
            if (offset < 0 || offset + size > data.lengthInBytes) return false;
            samples.add(_Sample(index, time, duration, size, sampleFlags, cto, offset));
            time += duration;
            offset += size;
          }
          dataEnd = offset;
        default:
          return false; // Sample groups, encryption, …: not cut.
      }
    }
    return true;
  }

  /// A fragment holding [samples] (decode times rebased by [base]).
  static Uint8List _fragment(Uint8List d, _Movie movie, List<_Sample> samples, int seq, int base) {
    final cto = samples.any((s) => s.cto != 0);
    final negative = samples.any((s) => s.cto < 0);
    final tfhd = _full('tfhd', 0, 0x020000, [movie.trackId]);
    final tfdt = _full('tfdt', 1, 0, [0, 0]);
    final decode = samples.first.time - base;
    ByteData.sublistView(tfdt)
      ..setUint32(12, decode ~/ 0x100000000)
      ..setUint32(16, decode % 0x100000000);
    final trun = _full('trun', negative ? 1 : 0, 0x01 | 0x100 | 0x200 | 0x400 | (cto ? 0x800 : 0), [
      samples.length,
      0, // data offset, set below
      for (final s in samples) ...[s.duration, s.size, s.flags, if (cto) s.cto.toUnsigned(32)],
    ]);
    final traf = _box('traf', [tfhd, tfdt, trun]);
    final moof = _box('moof', [
      _full('mfhd', 0, 0, [seq]),
      traf,
    ]);
    // trun's data offset: from the moof's start to the mdat's data.
    final trunAt = moof.length - trun.length;
    ByteData.sublistView(moof).setUint32(trunAt + 16, moof.length + 8);
    final mdat = BytesBuilder(copy: false);
    for (final s in samples) {
      mdat.add(Uint8List.sublistView(d, s.offset, s.offset + s.size));
    }
    return _concat([
      moof,
      _box('mdat', [mdat.takeBytes()]),
    ]);
  }
}

typedef _Defaults = ({int duration, int size, int flags});

/// The `moov` of a fragmented file with one track: [trackId], the media
/// [timescale] and the `trex` sample [defaults].
class _Movie {
  _Movie(this.box, this.trackId, this.timescale, this.defaults, this.durations);

  final _Box box;
  final int trackId, timescale;
  final _Defaults defaults;

  /// Where the durations sit: (offset, 64-bit, timescale, media time it
  /// starts at) for `mvhd`, `tkhd`, `mdhd`, `mehd` and a one-entry edit
  /// list (whose priming skip, e.g. AAC's 1024 samples, it keeps).
  final List<(int, bool, int, int)> durations;

  static _Movie? read(ByteData data, _Box moov) {
    _Box? only(_Box parent, String type) {
      final found = [
        for (final b in _boxes(data, parent.dataStart, parent.end))
          if (b.type == type) b,
      ];
      return found.length == 1 ? found.single : null;
    }

    final mvhd = only(moov, 'mvhd'), trak = only(moov, 'trak'), mvex = only(moov, 'mvex');
    if (mvhd == null || trak == null || mvex == null) return null;
    final tkhd = only(trak, 'tkhd'), mdia = only(trak, 'mdia');
    final mdhd = mdia == null ? null : only(mdia, 'mdhd');
    final trex = only(mvex, 'trex');
    if (tkhd == null || mdhd == null || trex == null) return null;
    bool v1(_Box b) => data.getUint8(b.dataStart) == 1;
    final movieScale = data.getUint32(mvhd.dataStart + (v1(mvhd) ? 20 : 12));
    final timescale = data.getUint32(mdhd.dataStart + (v1(mdhd) ? 20 : 12));
    final trackId = data.getUint32(tkhd.dataStart + (v1(tkhd) ? 20 : 12));
    if (timescale == 0 || movieScale == 0 || data.getUint32(trex.dataStart + 4) != trackId) {
      return null;
    }
    final mehd = only(mvex, 'mehd');
    final edts = only(trak, 'edts');
    final elst = edts == null ? null : only(edts, 'elst');
    (int, bool, int, int)? edit;
    if (elst != null && data.getUint32(elst.dataStart + 4) == 1) {
      final wide = v1(elst);
      final at = elst.dataStart + 8;
      final skip = wide ? _u64(data, at + 8) : data.getInt32(at + 4);
      if (skip >= 0 && skip < 0x7FFFFFFFFFFF) edit = (at, wide, movieScale, skip);
    }
    return _Movie(
      moov,
      trackId,
      timescale,
      (
        duration: data.getUint32(trex.dataStart + 12),
        size: data.getUint32(trex.dataStart + 16),
        flags: data.getUint32(trex.dataStart + 20),
      ),
      [
        (mvhd.dataStart + (v1(mvhd) ? 24 : 16), v1(mvhd), movieScale, 0),
        (tkhd.dataStart + (v1(tkhd) ? 28 : 20), v1(tkhd), movieScale, 0),
        (mdhd.dataStart + (v1(mdhd) ? 24 : 16), v1(mdhd), timescale, 0),
        if (mehd != null) (mehd.dataStart + 4, v1(mehd), movieScale, 0),
        ?edit,
      ],
    );
  }

  /// The `moov` with its (nonzero) durations set to [duration] (in the
  /// media timescale).
  Uint8List withDuration(Uint8List d, int duration) {
    final out = Uint8List.fromList(Uint8List.sublistView(d, box.start, box.end));
    final data = ByteData.sublistView(out);
    for (final (at, wide, scale, skip) in durations) {
      final o = at - box.start;
      final value = max(0, duration - skip) * scale ~/ timescale;
      if (wide) {
        if (_u64(data, o) == 0) continue;
        data
          ..setUint32(o, value ~/ 0x100000000)
          ..setUint32(o + 4, value % 0x100000000);
      } else if (data.getUint32(o) != 0) {
        data.setUint32(o, value.clamp(0, 0xFFFFFFFE));
      }
    }
    return out;
  }
}

/// One audio sample: its fragment, decode [time] and [duration] (media
/// timescale), [size], [flags], composition offset and file [offset].
class _Sample {
  _Sample(this.fragment, this.time, this.duration, this.size, this.flags, this.cto, this.offset);

  final int fragment, time, duration, size, flags, cto, offset;
}

/// A box: its [type], where it [start]s, its data starts and it [end]s.
typedef _Box = ({String type, int start, int dataStart, int end});

/// The boxes in [data]'s bytes [from]…[to]; throws [FormatException] when
/// they don't parse.
List<_Box> _boxes(ByteData data, int from, int to) {
  final out = <_Box>[];
  for (var pos = from; pos < to;) {
    if (pos + 8 > to) throw const FormatException('box header');
    var size = data.getUint32(pos);
    final type = String.fromCharCodes(Uint8List.sublistView(data, pos + 4, pos + 8));
    var header = 8;
    if (size == 1) {
      if (pos + 16 > to) throw const FormatException('box header');
      size = _u64(data, pos + 8);
      header = 16;
    } else if (size == 0) {
      size = to - pos;
    }
    if (size < header || size > to - pos) throw const FormatException('box size');
    out.add((type: type, start: pos, dataStart: pos + header, end: pos + size));
    pos += size;
  }
  return out;
}

/// A 64-bit unsigned integer, without 64-bit `ByteData` (browsers).
int _u64(ByteData data, int at) => data.getUint32(at) * 0x100000000 + data.getUint32(at + 4);

Uint8List _box(String type, List<Uint8List> body) {
  final size = 8 + body.fold<int>(0, (sum, b) => sum + b.length);
  final header = Uint8List(8);
  ByteData.sublistView(header).setUint32(0, size);
  header.setAll(4, type.codeUnits);
  return _concat([header, ...body]);
}

/// A full box (version, flags) whose body is the 32-bit [words].
Uint8List _full(String type, int version, int flags, List<int> words) {
  final body = Uint8List(4 + 4 * words.length);
  final data = ByteData.sublistView(body)..setUint32(0, version << 24 | flags);
  for (final (i, w) in words.indexed) {
    data.setUint32(4 + 4 * i, w);
  }
  return _box(type, [body]);
}

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  parts.forEach(out.add);
  return out.takeBytes();
}
