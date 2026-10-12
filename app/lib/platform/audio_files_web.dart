import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/blob_store.dart';

/// Browsers record into memory and return a blob URL; no target needed.
Future<String> newCaptureTarget(String extension) async => '';

/// Browsers never stream captures to files.
StreamSink<List<int>> openCaptureSink(String path) =>
    throw UnsupportedError('No files in browsers');

/// Frees a finished capture's blob URL.
Future<void> deleteCapture(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}

/// Browsers only allow the microphone on secure origins.
Future<String?> recordingUnavailableReason() async => web.window.isSecureContext
    ? null
    : 'Recording needs the app to be served over HTTPS (or from localhost).';

/// A blob URL for [shas] joined (read from IndexedDB into memory, which
/// browsers need for playback anyway; see `Recording.joinable`). Null if
/// one is not on the device.
Future<({String uri, bool isFile})?> audioUriFor(
  BlobStore blobs,
  List<String> shas,
  String mime,
) async {
  final parts = <JSUint8Array>[];
  for (final sha in shas) {
    final bytes = await blobs.read(sha);
    if (bytes == null) return null;
    parts.add(bytes.toJS);
  }
  final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: mime));
  return (uri: web.URL.createObjectURL(blob), isFile: false);
}

/// Frees a blob URL made by [audioUriFor].
void releaseAudioUri(String uri) {
  if (uri.startsWith('blob:')) web.URL.revokeObjectURL(uri);
}
