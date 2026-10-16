import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/file_names.dart';

/// Where exported files went (`platform/file_export`).
enum ExportedTo {
  /// Saved as a file (desktop: the path is known).
  file,

  /// Several files saved into a folder (desktop: the folder's path).
  folder,

  /// Saved through the system's file picker (Android "Save to device").
  device,

  /// Handed to the share sheet (Android).
  shared,

  /// Downloaded by the browser (which decides where).
  downloaded,
}

/// The outcome of handing exported files to the user.
class ExportedFiles {
  const ExportedFiles(this.to, {required this.count, this.name, this.path});

  final ExportedTo to;

  /// How many files.
  final int count;

  /// The file's name ([count] 1) or the folder's ([ExportedTo.folder]),
  /// as the user sees it.
  final String? name;

  /// The file or folder on disk, when there is one to show (desktop).
  final String? path;
}

/// Several exported [files] as one ZIP (browsers ask before a site
/// downloads several files, R22-7), named after [subject] as exported
/// files are ([safeFileName]: "Physics.zip") or "Len export.zip"; names
/// repeated inside, even only by case, get " (2)"… ([uniqueFileName]).
({Uint8List bytes, String name}) zipOf(
  List<({Uint8List bytes, String name})> files, {
  String? subject,
}) {
  final archive = Archive();
  final taken = <String>{};
  for (final f in files) {
    archive.add(ArchiveFile.bytes(uniqueFileName(f.name, taken), f.bytes));
  }
  return (
    bytes: ZipEncoder().encodeBytes(archive),
    name: '${safeFileName(subject ?? '', fallback: 'Len export')}.zip',
  );
}
