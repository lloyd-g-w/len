import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
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

/// A Len file being written to a temporary file named [name] (earlier
/// ones are deleted first: a share may still have needed them until now).
Future<LenFileOutput> createLenFileOutput(String name) async {
  final tmp = await getTemporaryDirectory();
  final dir = await Directory(p.join(tmp.path, 'len-files')).create(recursive: true);
  for (final old in dir.listSync()) {
    try {
      old.deleteSync(recursive: true);
    } on FileSystemException {
      // Still open elsewhere (Windows): left for next time.
    }
  }
  final path = p.join(dir.path, name);
  return LenFileOutput._(OutputFileStream(path), path, name);
}

/// A Len file being written; [deliver] or [discard] it when done.
class LenFileOutput {
  LenFileOutput._(this.stream, this._path, this.name);

  /// Where the file is written.
  final OutputFileStream stream;
  final String _path;

  /// The file's name as the user sees it.
  final String name;

  /// Closes the file and saves (desktop), shares or with [toDevice] saves
  /// (Android) it, as `saveOrShareFile` does; null if cancelled.
  Future<ExportedFiles?> deliver({required String mime, bool toDevice = false}) async {
    await stream.close();
    final mobile = Platform.isAndroid || Platform.isIOS;
    try {
      return await saveOrShareFile(_path, name: name, mime: mime, toDevice: toDevice);
    } finally {
      // A share sheet may still be reading it; the next Len file deletes it.
      if (!mobile || toDevice) await discard();
    }
  }

  /// Closes and deletes the file (cancelled or failed).
  Future<void> discard() async {
    await stream.close();
    final file = File(_path);
    if (file.existsSync()) await file.delete();
  }
}
