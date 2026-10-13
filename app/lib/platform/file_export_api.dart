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
