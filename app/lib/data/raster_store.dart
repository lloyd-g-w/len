import 'dart:collection';
import 'dart:typed_data';

/// Keeps encoded images (level-of-detail rasters of chunks) across
/// restarts, by name, within a size budget: least recently used first out.
///
/// A cache: anything may be gone when asked for again. Files natively
/// (`platform/raster_store_native.dart`); browsers have none (the web
/// rasterises chunks again every time, as before), tests use
/// [MemoryRasterStore].
abstract interface class RasterStore {
  /// The bytes stored as [name], or null.
  Future<Uint8List?> read(String name);

  /// Stores [bytes] as [name] (replacing what was there), evicting the
  /// least recently used entries beyond the budget.
  Future<void> write(String name, Uint8List bytes);
}

/// Keeps rasters in memory, LRU over [maxBytes] (tests).
class MemoryRasterStore implements RasterStore {
  MemoryRasterStore({this.maxBytes = 1 << 30});

  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();
  int _bytes = 0;

  /// Reads and writes so far (tests count them).
  int reads = 0, writes = 0;

  int get length => _entries.length;

  Iterable<String> get names => _entries.keys;

  @override
  Future<Uint8List?> read(String name) async {
    reads++;
    final bytes = _entries.remove(name);
    if (bytes != null) _entries[name] = bytes;
    return bytes;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    writes++;
    final old = _entries.remove(name);
    if (old != null) _bytes -= old.length;
    _entries[name] = bytes;
    _bytes += bytes.length;
    while (_bytes > maxBytes && _entries.length > 1) {
      _bytes -= _entries.remove(_entries.keys.first)!.length;
    }
  }
}
