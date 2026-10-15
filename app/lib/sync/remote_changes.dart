import '../data/deletion_conflicts.dart';

/// What a pull changed locally, so open screens can refresh.
class RemoteChanges {
  RemoteChanges();

  bool notebooks = false;

  /// Whether any library folder changed.
  bool folders = false;

  /// Whether any of the user's templates changed.
  bool templates = false;

  /// Notebooks whose page list changed.
  final Set<String> pagesOfNotebooks = {};

  /// Surfaces (pages / canvases) whose content (strokes or elements) changed.
  final Set<String> strokeSurfaces = {};

  /// Notebooks whose own outline changed.
  final Set<String> outlineOfNotebooks = {};

  /// Notebooks whose audio recordings changed.
  final Set<String> recordingsOfNotebooks = {};

  /// Whether deleted content came back (see `DeletionConflicts`); it is
  /// local edits to push.
  bool revived = false;

  /// Adds what [revival] brought back.
  void addRevival(Revival revival) {
    if (revival.isEmpty) return;
    revived = notebooks = true;
    pagesOfNotebooks.addAll(revival.notebooks);
    recordingsOfNotebooks.addAll(revival.notebooks);
    outlineOfNotebooks.addAll(revival.notebooks);
    strokeSurfaces.addAll(revival.surfaces);
  }

  /// Adds what [other] changed.
  void addAll(RemoteChanges other) {
    notebooks |= other.notebooks;
    folders |= other.folders;
    templates |= other.templates;
    revived |= other.revived;
    pagesOfNotebooks.addAll(other.pagesOfNotebooks);
    strokeSurfaces.addAll(other.strokeSurfaces);
    outlineOfNotebooks.addAll(other.outlineOfNotebooks);
    recordingsOfNotebooks.addAll(other.recordingsOfNotebooks);
  }

  bool get isEmpty =>
      !notebooks &&
      !folders &&
      !templates &&
      pagesOfNotebooks.isEmpty &&
      strokeSurfaces.isEmpty &&
      recordingsOfNotebooks.isEmpty &&
      outlineOfNotebooks.isEmpty;
}
