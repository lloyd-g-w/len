import 'package:flutter/foundation.dart';

import '../data/write_back.dart';

/// Size of the blocks files are stored in.
const writeBackBlockSize = 4096;

/// Durable storage for [WriteBackFileSystem]: files as blocks of
/// [writeBackBlockSize] bytes (IndexedDB on the web; fakes in tests).
abstract interface class BlockStore {
  /// Every stored file's content.
  Future<Map<String, Uint8List>> readAll();

  /// Applies [changes] atomically: all of them or (throwing) none.
  /// Throws [StorageFullException] when out of space.
  Future<void> commit(List<FileChange> changes);

  void close();
}

/// A change to one stored file.
class FileChange {
  const FileChange.delete(this.path) : length = null, blocks = const {}, replace = false;

  const FileChange.write(
    this.path, {
    required int this.length,
    required this.blocks,
    this.replace = false,
  });

  final String path;

  /// The file's new length; null if the file is deleted.
  final int? length;

  /// New content of the blocks that changed, by offset; each block is
  /// [writeBackBlockSize] long (zero-padded past [length]).
  final Map<int, Uint8List> blocks;

  /// Whether every other stored block of the file is dropped (a new file).
  final bool replace;

  bool get deleted => length == null;
}
