import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/raster_store.dart';

/// Opens the level-of-detail raster cache: files in the app's cache
/// directory (the system may clear it; it is only a cache), `lod-<format>`.
/// Directories of other formats (rasters drawn by an older renderer) are
/// deleted.
Future<RasterStore?> openRasterStore({required int format, int maxBytes = 96 << 20}) async {
  try {
    final cache = await getApplicationCacheDirectory();
    final name = 'lod-$format';
    if (cache.existsSync()) {
      for (final old in cache.listSync().whereType<Directory>()) {
        final base = p.basename(old.path);
        if (base.startsWith('lod-') && base != name) unawaited(old.delete(recursive: true));
      }
    }
    return FileRasterStore(p.join(cache.path, name), maxBytes: maxBytes);
  } on Object catch (e) {
    debugPrint('No raster cache: $e');
    return null;
  }
}

/// One file per raster in [directory], LRU by file modification time
/// (refreshed on reads) within [maxBytes].
///
/// The directory is listed in the background when opened; until then
/// reads go straight to the files and eviction waits.
class FileRasterStore implements RasterStore {
  FileRasterStore(this.directory, {this.maxBytes = 96 << 20}) {
    _scanned = _scan();
  }

  final String directory;
  final int maxBytes;

  /// Sizes of the stored files, least recently used first.
  final LinkedHashMap<String, int> _sizes = LinkedHashMap();
  int _bytes = 0;
  int _temp = 0;
  late final Future<void> _scanned;

  /// Completes once the directory has been listed.
  Future<void> get ready => _scanned;

  File _file(String name) => File(p.join(directory, name));

  Future<void> _scan() async {
    final dir = Directory(directory);
    final found = <(String, int, DateTime)>[];
    try {
      await dir.create(recursive: true);
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (name.endsWith('.tmp')) {
          unawaited(entry.delete().then((_) {}, onError: (_) {}));
          continue;
        }
        final stat = await entry.stat();
        found.add((name, stat.size, stat.modified));
      }
    } on FileSystemException catch (e) {
      debugPrint('Cannot list the raster cache: $e');
    }
    found.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (name, size, _) in found) {
      _sizes[name] = size;
      _bytes += size;
    }
    await _evict();
  }

  @override
  Future<Uint8List?> read(String name) async {
    final file = _file(name);
    try {
      final bytes = await file.readAsBytes();
      final size = _sizes.remove(name);
      if (size != null) _sizes[name] = size; // Most recently used.
      unawaited(file.setLastModified(DateTime.now()).then((_) {}, onError: (_) {}));
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes to a temporary file first, so a crash never leaves a truncated
  /// raster under its name.
  @override
  Future<void> write(String name, Uint8List bytes) async {
    await _scanned; // The directory exists.
    final target = _file(name);
    final temp = File('${target.path}.${_temp++}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: false);
      await temp.rename(target.path);
    } on FileSystemException catch (e) {
      debugPrint('Cannot store raster $name: $e');
      unawaited(temp.delete().then((_) {}, onError: (_) {}));
      return;
    }
    final old = _sizes.remove(name);
    if (old != null) _bytes -= old;
    _sizes[name] = bytes.length;
    _bytes += bytes.length;
    await _evict();
  }

  @override
  Future<int> size() async {
    await _scanned;
    return _bytes;
  }

  /// Deletes the files listed (a raster being written meanwhile stays,
  /// counted, and goes by the budget as usual).
  @override
  Future<void> clear() async {
    await _scanned;
    final names = _sizes.keys.toList();
    _sizes.clear();
    _bytes = 0;
    for (final name in names) {
      try {
        await _file(name).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  Future<void> _evict() async {
    while (_bytes > maxBytes && _sizes.length > 1) {
      final oldest = _sizes.keys.first;
      _bytes -= _sizes.remove(oldest)!;
      try {
        await _file(oldest).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }
}
