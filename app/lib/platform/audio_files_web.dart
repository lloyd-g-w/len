import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/blob_store.dart';

/// Browsers record into memory and return a blob URL; no target needed.
Future<String> newCaptureTarget(String extension) async => '';

/// Frees a finished capture's blob URL.
Future<void> deleteCapture(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}

/// Browsers only allow the microphone on secure origins.
Future<String?> recordingUnavailableReason() async => web.window.isSecureContext
    ? null
    : 'Recording needs the app to be served over HTTPS (or from localhost).';

/// A blob URL for blob [sha] (read from IndexedDB into memory, which
/// browsers need for playback anyway). Null if it is not on the device.
Future<({String uri, bool isFile})?> audioUriFor(BlobStore blobs, String sha, String mime) async {
  final bytes = await blobs.read(sha);
  if (bytes == null) return null;
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  return (uri: web.URL.createObjectURL(blob), isFile: false);
}

/// Frees a blob URL made by [audioUriFor].
void releaseAudioUri(String uri) {
  if (uri.startsWith('blob:')) web.URL.revokeObjectURL(uri);
}
