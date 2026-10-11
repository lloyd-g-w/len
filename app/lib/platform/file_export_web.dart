import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [bytes] as [name] (the browser decides where it goes) and
/// returns [name].
Future<String?> saveOrShare(Uint8List bytes, {required String name, required String mime}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoking immediately can cancel the download in some browsers.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return name;
}

/// Downloads each of [files]; returns how many as "3 files" (or the one
/// file's name).
Future<String?> saveOrShareAll(
  List<({Uint8List bytes, String name})> files, {
  required String mime,
}) async {
  for (final (i, f) in files.indexed) {
    // Browsers drop rapid successive downloads; space them out a little.
    if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 250));
    await saveOrShare(f.bytes, name: f.name, mime: mime);
  }
  return files.length == 1 ? files.single.name : '${files.length} files';
}
