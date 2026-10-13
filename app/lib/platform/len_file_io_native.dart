import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_export_api.dart';
import 'file_export_native.dart';

/// File [path] for reading in chunks, or null if there is none.
InputStream? openFileInput(String path) => File(path).existsSync() ? InputFileStream(path) : null;

/// [file] for reading: in place when it is a file here, else from memory.
Future<InputStream> openPickedInput(XFile file) async =>
    (file.path.isEmpty ? null : openFileInput(file.path)) ??
    InputMemoryStream(await file.readAsBytes());

/// Whether a Len file is written without being held in memory: always,
/// natively (into a file).
bool get lenFilesStream => true;

bool get _mobile =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Starts a Len file named [name]. Desktop: asks where to save it first
/// (UX_AUDIT R8-18), then writes it there (as a `.part` file until it is
/// done); null if cancelled. Mobile: writes a temporary file, to share or
/// with [toDevice] (Android) save when done (earlier ones are deleted
/// first: a share may still have needed them until now).
Future<LenFileOutput?> createLenFileOutput(
  String name, {
  required String mime,
  bool toDevice = false,
}) async {
  if (!_mobile) {
    final path = await askSaveLocation(name, mime: mime);
    if (path == null) return null;
    return LenFileOutput._(OutputFileStream('$path.part'), '$path.part', name, mime, to: path);
  }
  final tmp = await getTemporaryDirectory();
  final dir = await Directory(p.join(tmp.path, 'len-files')).create(recursive: true);
  for (final old in dir.listSync()) {
    try {
      old.deleteSync(recursive: true);
    } on FileSystemException {
      // Still open elsewhere: left for next time.
    }
  }
  final path = p.join(dir.path, name);
  return LenFileOutput._(OutputFileStream(path), path, name, mime, toDevice: toDevice);
}

/// A Len file being written; [deliver] or [discard] it when done.
class LenFileOutput {
  LenFileOutput._(this.stream, this._path, this.name, this._mime, {this.to, this.toDevice = false});

  /// Where the file is written.
  final OutputFileStream stream;
  final String _path;

  /// The file's name as the user sees it.
  final String name;
  final String _mime;

  /// The chosen path (desktop), or null to share when done (mobile).
  final String? to;
  final bool toDevice;

  /// Waits until what was written has left memory: at once, here.
  Future<void> drain() async {}

  /// Closes the file and puts it where it was asked to go (desktop), or
  /// shares or saves it (mobile); null if cancelled.
  Future<ExportedFiles?> deliver() async {
    await stream.close();
    final to = this.to;
    if (to != null) {
      await File(_path).rename(to);
      return ExportedFiles(ExportedTo.file, count: 1, name: p.basename(to), path: to);
    }
    try {
      return await shareFile(_path, name: name, mime: _mime, toDevice: toDevice);
    } finally {
      // A share sheet may still be reading it; the next Len file deletes it.
      if (toDevice) await discard();
    }
  }

  /// Closes and deletes the file (cancelled or failed).
  Future<void> discard() async {
    await stream.close();
    final file = File(_path);
    if (file.existsSync()) await file.delete();
  }
}
