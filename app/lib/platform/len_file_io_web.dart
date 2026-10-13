import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'chunked_output.dart';
import 'file_export_api.dart';
import 'file_export_web.dart';

/// Browsers keep blobs in IndexedDB, not files.
InputStream? openFileInput(String path) => null;

/// [file] read into memory.
Future<InputStream> openPickedInput(XFile file) async =>
    InputMemoryStream(await file.readAsBytes());

/// Whether a Len file is written without being held in memory: where the
/// browser can save files as they are written (`showSaveFilePicker`).
/// Elsewhere it is kept as a browser blob (of chunks, which the browser
/// may keep on disk), then downloaded.
bool get lenFilesStream => globalContext.has('showSaveFilePicker');

@JS('showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle> _showSaveFilePicker(_SaveOptions options);

extension type _SaveOptions._(JSObject _) implements JSObject {
  external factory _SaveOptions({String suggestedName});
}

/// Starts a Len file named [name] (UX_AUDIT R8-17): where the browser has
/// a save picker, asks where first and writes straight into that file
/// (null if cancelled); elsewhere into a blob of chunks, downloaded when
/// done. [toDevice] is ignored.
Future<LenFileOutput?> createLenFileOutput(
  String name, {
  required String mime,
  bool toDevice = false,
}) async {
  if (lenFilesStream) {
    try {
      final handle = await _showSaveFilePicker(_SaveOptions(suggestedName: name)).toDart;
      final writable = await handle.createWritable().toDart;
      return LenFileOutput._file(handle.name, mime, writable);
    } on Object catch (e) {
      if (e.toString().contains('AbortError')) return null; // Cancelled.
      // No user gesture left, or not allowed here: download instead.
      debugPrint('Save picker unavailable: $e');
    }
  }
  return LenFileOutput._download(name, mime);
}

/// A Len file being written; [deliver] or [discard] it when done.
class LenFileOutput {
  LenFileOutput._file(this.name, this._mime, web.FileSystemWritableFileStream this._writable) {
    stream = ChunkedOutput((chunk) {
      _pending = _pending.then((_) => _writable!.write(chunk.toJS).toDart);
    });
  }

  LenFileOutput._download(this.name, this._mime) : _writable = null {
    stream = ChunkedOutput((chunk) => _parts.add(web.Blob([chunk.toJS].toJS)));
  }

  /// Where the file is written.
  late final ChunkedOutput stream;

  /// The file's name as the user sees it.
  final String name;
  final String _mime;

  final web.FileSystemWritableFileStream? _writable;
  Future<void> _pending = Future.value();
  final List<web.Blob> _parts = [];

  /// Waits until what was written has gone to the file, so memory holds
  /// at most a few chunks.
  Future<void> drain() => _pending;

  /// Finishes the file: saves it where chosen, or downloads it.
  Future<ExportedFiles?> deliver() async {
    stream.flush();
    final writable = _writable;
    if (writable == null) {
      final blob = web.Blob(_parts.toJS, web.BlobPropertyBag(type: _mime));
      _parts.clear();
      return downloadBlob(blob, name: name);
    }
    await _pending;
    await writable.close().toDart;
    return ExportedFiles(ExportedTo.file, count: 1, name: name);
  }

  /// Drops the file.
  Future<void> discard() async {
    stream.clear();
    _parts.clear();
    final writable = _writable;
    if (writable == null) return;
    try {
      await _pending;
    } on Object {
      // Already failed: aborting below is all that is left.
    }
    await writable.abort().toDart;
  }
}
