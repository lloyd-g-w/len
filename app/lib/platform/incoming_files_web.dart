import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Links Len was opened with: none on the web.
Stream<String> get incomingLinks => const Stream.empty();

/// Files the installed PWA was opened with (File Handling API: "Open with
/// Len" in the OS, see `file_handlers` in `web/manifest.json`). Browsers
/// without `launchQueue` deliver nothing. [args] are unused.
Stream<List<XFile>> openIncomingFiles(List<String> args) {
  final window = web.window as JSObject;
  if (!window.has('launchQueue')) return const Stream.empty();
  final controller = StreamController<List<XFile>>();
  void consume(JSObject params) {
    final handles = params['files'] as JSArray<web.FileSystemFileHandle>?;
    if (handles == null) return;
    unawaited(
      _read(handles.toDart).then(
        controller.add,
        onError: (Object e) {
          debugPrint('Couldn’t read launched files: $e');
        },
      ),
    );
  }

  (window['launchQueue']! as JSObject).callMethod<JSAny?>('setConsumer'.toJS, consume.toJS);
  return controller.stream;
}

Future<List<XFile>> _read(List<web.FileSystemFileHandle> handles) async {
  final files = <XFile>[];
  for (final handle in handles) {
    final file = await handle.getFile().toDart;
    final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
    files.add(XFile.fromData(bytes, name: file.name, mimeType: file.type, length: bytes.length));
  }
  return files;
}
