import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The UTF-8 text [deflated] (raw deflate, as in a zip) holds, inflated by
/// the browser's `DecompressionStream` and decoded by its `TextDecoder`,
/// neither on the UI thread's Dart. Null where the browser has no
/// `deflate-raw` stream (the caller inflates in Dart). Throws if the data
/// is damaged (not deflate, or not UTF-8).
Future<String?> inflateUtf8Text(Uint8List deflated) async {
  final web.DecompressionStream inflater;
  try {
    inflater = web.DecompressionStream('deflate-raw');
  } on Object {
    return null; // No DecompressionStream, or no raw deflate (older browsers).
  }
  final pair = web.ReadableWritablePair(readable: inflater.readable, writable: inflater.writable);
  final input = web.Blob([deflated.toJS].toJS).stream();
  final buffer = await web.Response(input.pipeThrough(pair)).arrayBuffer().toDart;
  return web.TextDecoder('utf-8', web.TextDecoderOptions(fatal: true)).decode(buffer);
}
