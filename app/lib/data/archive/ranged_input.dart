import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reads bytes [start] to [end] (exclusive) of a file.
typedef RangeRead = Future<Uint8List> Function(int start, int end);

/// A file too big to hold in memory that can only be read asynchronously,
/// in slices (a file picked in a browser: `Blob.slice`), made readable by
/// the synchronous zip decoder: what it will read is loaded first ([load]),
/// and only that is kept. Reading a byte that wasn't loaded is a bug and
/// throws a [StateError].
class RangedFile {
  RangedFile(this.size, this._read);

  /// The file's size in bytes.
  final int size;
  final RangeRead _read;

  /// Kept slices (the zip's structure), sorted by start, not overlapping.
  final List<_Slice> _kept = [];

  /// The slice of content read last (dropped when the next one loads).
  _Slice? _content;
  _Slice? _last;

  /// The bytes held in memory now.
  int get held => _kept.fold(_content?.bytes.length ?? 0, (sum, s) => sum + s.bytes.length);

  /// Loads bytes [start] to [end]: [keep] them (the zip's directory and
  /// headers, read again and again), or hold them only until the next
  /// content loads (an entry's data).
  Future<void> load(int start, int end, {bool keep = false}) async {
    start = start.clamp(0, size);
    end = end.clamp(start, size);
    if (end == start || (keep ? _keeps : _covered)(start, end)) return;
    final bytes = await _read(start, end);
    if (bytes.length != end - start) {
      throw StateError('Read ${bytes.length} bytes of $start…$end');
    }
    final slice = _Slice(start, bytes);
    if (!keep) {
      _content = slice;
      _last = null;
      return;
    }
    _keep(slice);
  }

  /// Adds [slice] to [_kept] unless a kept one holds it, dropping those
  /// inside it: no kept slice lies inside another, so the last one starting
  /// at or before a byte is the one to look in.
  void _keep(_Slice slice) {
    if (_keeps(slice.start, slice.end)) return;
    _kept.removeWhere((k) => k.start >= slice.start && k.end <= slice.end);
    final at = _kept.indexWhere((k) => k.start > slice.start);
    _kept.insert(at < 0 ? _kept.length : at, slice);
    _last = null;
  }

  /// Loads the [ranges] to keep (the parts within the file), joining those
  /// less than [gap] apart into one read, a few reads at a time.
  Future<void> keepAll(List<(int, int)> ranges, {int gap = 4096}) async {
    final sorted = [
      for (final (s, e) in ranges)
        if (math.min(e, size) > math.max(s, 0)) (math.max(s, 0), math.min(e, size)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (sorted.isEmpty) return;
    final joined = <(int, int)>[sorted.first];
    for (final (start, end) in sorted.skip(1)) {
      final (s, e) = joined.last;
      if (start <= e + gap) {
        joined.last = (s, math.max(e, end));
      } else {
        joined.add((start, end));
      }
    }
    final todo = [
      for (final (s, e) in joined)
        if (!_keeps(s, e)) (s, e),
    ];
    for (var i = 0; i < todo.length; i += 16) {
      final batch = todo.sublist(i, math.min(i + 16, todo.length));
      final read = await Future.wait([for (final (s, e) in batch) _read(s, e)]);
      for (final (k, (s, e)) in batch.indexed) {
        if (read[k].length != e - s) throw StateError('Read ${read[k].length} bytes of $s…$e');
        _keep(_Slice(s, read[k]));
      }
    }
  }

  bool _covered(int start, int end) {
    final slice = _sliceAt(start);
    return slice != null && slice.end >= end;
  }

  /// Whether a kept slice holds bytes [start] to [end] (the content slice
  /// is dropped when the next one loads, so it does not count).
  bool _keeps(int start, int end) {
    final slice = _keptAt(start);
    return slice != null && slice.end >= end;
  }

  _Slice? _sliceAt(int at) {
    final last = _last;
    if (last != null && last.contains(at)) return last;
    final content = _content;
    if (content != null && content.contains(at)) return _last = content;
    if (_keptAt(at) case final kept?) return _last = kept;
    return null;
  }

  /// The kept slice holding byte [at]: the last starting at or before it.
  _Slice? _keptAt(int at) {
    var lo = 0, hi = _kept.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_kept[mid].start <= at) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found >= 0 && _kept[found].contains(at) ? _kept[found] : null;
  }

  /// The byte at [at].
  int byteAt(int at) {
    final slice = _sliceAt(at);
    if (slice == null) throw StateError('Byte $at of the file was not loaded');
    return slice.bytes[at - slice.start];
  }

  /// Bytes [start] to [end].
  Uint8List bytes(int start, int end) {
    if (end <= start) return Uint8List(0);
    final slice = _sliceAt(start);
    if (slice != null && slice.end >= end) {
      return Uint8List.sublistView(slice.bytes, start - slice.start, end - slice.start);
    }
    return Uint8List.fromList([for (var i = start; i < end; i++) byteAt(i)]);
  }
}

class _Slice {
  _Slice(this.start, this.bytes);

  final int start;
  final Uint8List bytes;
  int get end => start + bytes.length;
  bool contains(int at) => at >= start && at < end;
}

/// A window onto a [RangedFile] as an archive [InputStream] (the whole
/// file, or a part of it: [subset]).
class RangedInput extends InputStream {
  RangedInput(this.file, {int start = 0, int? length})
    : _start = start,
      _length = length ?? file.size - start,
      super(byteOrder: ByteOrder.littleEndian);

  final RangedFile file;
  final int _start, _length;
  int _position = 0;

  /// Loads the next [count] bytes from the read position (an entry's data,
  /// read in pieces).
  Future<void> loadNext(int count) {
    final from = _start + _position;
    return file.load(from, math.min(from + count, _start + _length));
  }

  /// Loads what is left from the read position (an entry's data).
  Future<void> loadRest() => loadNext(_length - _position);

  @override
  int get position => _position;

  @override
  set position(int v) => setPosition(v);

  /// How many bytes are left.
  @override
  int get length => _length - _position;

  @override
  bool get isEOS => _position >= _length;

  @override
  bool open() => true;

  @override
  Future<void> close() async => _position = 0;

  @override
  void closeSync() => _position = 0;

  @override
  void reset() => _position = 0;

  @override
  void setPosition(int v) => _position = v;

  @override
  void rewind([int length = 1]) => _position = (_position - length).clamp(0, _length);

  @override
  void skip(int length) => _position = (_position + length).clamp(0, _length);

  @override
  InputStream subset({int? position, int? length, int? bufferSize}) {
    position ??= _position;
    position = position.clamp(0, _length);
    final available = _length - position;
    length ??= available;
    if (length < 0 || length > available) length = available;
    return RangedInput(file, start: _start + position, length: length);
  }

  @override
  int readByte() {
    if (_position >= _length) throw RangeError.index(_position, this);
    return file.byteAt(_start + _position++);
  }

  @override
  Uint8List toUint8List() => file.bytes(_start + _position, _start + _length);
}
