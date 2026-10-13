import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../data/blob_backend.dart';
import '../data/write_back.dart';

/// Opens the app's blob storage: files under `<directory>/blobs` (written
/// synchronously from the caller's view, so nothing joins [writes]).
Future<BlobBackend> openBlobBackend(String directory, {StorageWrites? writes}) async =>
    FileBlobBackend(p.join(directory, 'blobs'));

/// Stores each blob as a file `<directory>/<sha[0..2]>/<sha>`.
class FileBlobBackend implements BlobBackend {
  FileBlobBackend(this.directory);

  final String directory;
  int _tempCounter = 0;

  File _file(String sha) => File(p.join(directory, sha.substring(0, 2), sha));

  @override
  Future<bool> contains(String sha) => _file(sha).exists();

  @override
  Future<Uint8List?> read(String sha) async {
    final file = _file(sha);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Stream<List<int>> openRead(String sha) {
    final file = _file(sha);
    return file.existsSync() ? file.openRead() : const Stream.empty();
  }

  /// Writes to a temporary file first, so a crash never leaves a truncated
  /// file under a blob's name.
  @override
  Future<void> write(String sha, Stream<List<int>> data) async {
    final target = _file(sha);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.$pid.${_tempCounter++}.tmp');
    try {
      final sink = temp.openWrite();
      try {
        await sink.addStream(data);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temp.rename(target.path);
    } catch (_) {
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String sha) async {
    final file = _file(sha);
    if (await file.exists()) await file.delete();
  }

  @override
  String? localPath(String sha) => _file(sha).path;
}
