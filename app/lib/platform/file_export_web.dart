import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_export_api.dart';

/// Browsers download; there is no separate save dialog.
bool get canSaveToDevice => false;

/// Browsers can't open folders.
bool get canShowInFolder => false;

/// Downloads [bytes] as [name] (the browser decides where it goes).
/// [toDevice] and [subject] are ignored.
Future<ExportedFiles?> saveOrShare(
  Uint8List bytes, {
  required String name,
  required String mime,
  bool toDevice = false,
  String? subject,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  return downloadBlob(blob, name: name);
}

/// Downloads [blob] as [name] (the browser decides where it goes).
ExportedFiles downloadBlob(web.Blob blob, {required String name}) {
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
  return ExportedFiles(ExportedTo.downloaded, count: 1, name: name);
}

/// Downloads each of [files].
Future<ExportedFiles?> saveOrShareAll(
  List<({Uint8List bytes, String name})> files, {
  required String mime,
  bool toDevice = false,
  String? subject,
}) async {
  for (final (i, f) in files.indexed) {
    // Browsers drop rapid successive downloads; space them out a little.
    if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 250));
    await saveOrShare(f.bytes, name: f.name, mime: mime);
  }
  return ExportedFiles(
    ExportedTo.downloaded,
    count: files.length,
    name: files.length == 1 ? files.single.name : null,
  );
}

/// Browsers can't open folders.
Future<void> showInFolder(String path) async {}
