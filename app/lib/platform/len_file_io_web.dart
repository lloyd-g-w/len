import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';

import 'file_export_api.dart';
import 'file_export_web.dart';

/// Browsers keep blobs in IndexedDB, not files.
InputStream? openFileInput(String path) => null;

/// [file] read into memory.
Future<InputStream> openPickedInput(XFile file) async =>
    InputMemoryStream(await file.readAsBytes());

/// A Len file written to memory, then downloaded.
Future<LenFileOutput> createLenFileOutput(String name) async => LenFileOutput._(name);

/// A Len file being written; [deliver] or [discard] it when done.
class LenFileOutput {
  LenFileOutput._(this.name);

  /// Where the file is written.
  final OutputMemoryStream stream = OutputMemoryStream();

  /// The file's name as the user sees it.
  final String name;

  /// Downloads the file.
  Future<ExportedFiles?> deliver({required String mime, bool toDevice = false}) =>
      saveOrShare(stream.getBytes(), name: name, mime: mime);

  /// Drops the file.
  Future<void> discard() async => stream.clear();
}
