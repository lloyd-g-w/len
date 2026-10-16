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

/// Downloads [files]: one as it is, several as one ZIP named after
/// [subject] (browsers block a site's run of downloads, R22-7).
Future<ExportedFiles?> saveOrShareAll(
  List<({Uint8List bytes, String name})> files, {
  required String mime,
  bool toDevice = false,
  String? subject,
}) async {
  if (files.length == 1) {
    return saveOrShare(files.single.bytes, name: files.single.name, mime: mime);
  }
  final zip = zipOf(files, subject: subject);
  await saveOrShare(zip.bytes, name: zip.name, mime: 'application/zip');
  return ExportedFiles(ExportedTo.downloaded, count: files.length, name: zip.name);
}

/// Browsers can't open folders.
Future<void> showInFolder(String path) async {}
