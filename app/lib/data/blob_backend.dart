import 'dart:async';
import 'dart:typed_data';

/// Where a [BlobStore] keeps blob bytes: files on native platforms
/// (`platform/blob_backend_native.dart`), IndexedDB in browsers
/// (`platform/blob_backend_web.dart`), memory in tests.
///
/// Blobs are content-addressed and immutable, so a backend only ever
/// writes a blob once and never changes it.
abstract interface class BlobBackend {
  /// Whether blob [sha] is stored.
  Future<bool> contains(String sha);

  /// The blob's bytes, or null if it is not stored.
  Future<Uint8List?> read(String sha);

  /// The blob's bytes in chunks (for uploads); empty if it is not stored.
  Stream<List<int>> openRead(String sha);

  /// Stores [data] as blob [sha], atomically: a failed or interrupted
  /// write never leaves a partial blob behind.
  Future<void> write(String sha, Stream<List<int>> data);

  /// The file holding blob [sha], when the platform has files (native);
  /// null in browsers. Lets large PDFs be opened without loading them
  /// into memory.
  String? localPath(String sha);
}

/// Keeps blobs in memory (tests; never persisted).
class MemoryBlobBackend implements BlobBackend {
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<bool> contains(String sha) async => _blobs.containsKey(sha);

  @override
  Future<Uint8List?> read(String sha) async => _blobs[sha];

  @override
  Stream<List<int>> openRead(String sha) {
    final bytes = _blobs[sha];
    return bytes == null ? const Stream.empty() : Stream.value(bytes);
  }

  @override
  Future<void> write(String sha, Stream<List<int>> data) async =>
      _blobs[sha] = await collectBytes(data);

  @override
  String? localPath(String sha) => null;
}

/// Concatenates a byte stream.
Future<Uint8List> collectBytes(Stream<List<int>> data) async {
  final builder = BytesBuilder(copy: false);
  await data.forEach(builder.add);
  return builder.takeBytes();
}
