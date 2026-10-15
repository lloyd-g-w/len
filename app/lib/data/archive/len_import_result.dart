import 'len_format.dart';

/// What an import brought in.
class LenImportResult {
  LenImportResult({
    required this.manifest,
    required this.notebooks,
    required this.folders,
    required this.folder,
    required this.skipped,
    required this.missingBlobs,
    this.lostParts = 0,
    this.problems = const [],
  });

  final LenManifest manifest;

  /// The new notebooks' ids.
  final List<String> notebooks;

  /// The folders made (the backup's own folder too).
  final List<String> folders;

  /// The folder holding what was imported (the backup's folder, or the
  /// copy of an exported folder); null when it went to the given parent.
  final String? folder;

  /// Records that could not be read (malformed or damaged), left out.
  final int skipped;

  /// Files (PDFs, images, audio) the Len file lacked or held damaged:
  /// shown as missing.
  final int missingBlobs;

  /// Parts of the records that were damaged as a whole (left out).
  final int lostParts;

  /// What was damaged, in technical words (for Details).
  final List<String> problems;

  /// Whether nothing was left out.
  bool get complete => skipped == 0 && missingBlobs == 0 && lostParts == 0;
}
