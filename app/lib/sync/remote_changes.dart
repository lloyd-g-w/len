import '../data/deletion_conflicts.dart';

/// What a pull changed locally, so open screens can refresh.
class RemoteChanges {
  RemoteChanges();

  bool notebooks = false;

  /// Whether any library folder changed.
  bool folders = false;

  /// How many notebook and folder records were applied (summed when
  /// merged): a long pull's progress tells by it whether the library has
  /// news since it last heard.
  int libraryWrites = 0;

  /// Whether any of the user's templates changed.
  bool templates = false;

  /// Notebooks whose page list changed.
  final Set<String> pagesOfNotebooks = {};

  /// Surfaces (pages / canvases) whose content (strokes or elements) changed.
  final Set<String> strokeSurfaces = {};

  /// Per surface of [strokeSurfaces], the strokes and elements that changed
  /// (see [itemsOf]).
  final Map<String, Set<String>> _items = {};

  /// Surfaces where more items changed than are worth naming, or where
  /// which ones is not known.
  final Set<String> _manyItems = {};

  /// Items named per surface at most; beyond, open views reload it.
  static const maxItems = 500;

  /// Notes that stroke or element [id] on [surface] changed.
  void addItem(String surface, String id) {
    strokeSurfaces.add(surface);
    if (_manyItems.contains(surface)) return;
    final ids = _items.putIfAbsent(surface, () => {})..add(id);
    if (ids.length > maxItems) _manyChanged(surface);
  }

  /// The strokes and elements on [surface] that changed, or null when that
  /// is not known or too many (reload the surface).
  Set<String>? itemsOf(String surface) => _manyItems.contains(surface) ? null : _items[surface];

  void _manyChanged(String surface) {
    strokeSurfaces.add(surface);
    _items.remove(surface);
    _manyItems.add(surface);
  }

  /// Notebooks whose own outline changed.
  final Set<String> outlineOfNotebooks = {};

  /// Notebooks whose audio recordings changed.
  final Set<String> recordingsOfNotebooks = {};

  /// Notebooks whose version history changed.
  final Set<String> versionsOfNotebooks = {};

  /// Notes that the content of [surface] changed whole (open views reload
  /// it), as a restore does.
  void reloadSurface(String surface) => _manyChanged(surface);

  /// Whether deleted content came back (see `DeletionConflicts`); it is
  /// local edits to push.
  bool revived = false;

  /// Notebooks and pages this device had deleted that came back because
  /// another device wrote in them ([Revival.undoneNotebooks],
  /// [Revival.undonePages]).
  final Set<String> undoneNotebooks = {};
  final Map<String, Set<String>> undonePages = {};

  /// Adds what [revival] brought back.
  void addRevival(Revival revival) {
    if (revival.isEmpty) return;
    revived = notebooks = true;
    libraryWrites++;
    pagesOfNotebooks.addAll(revival.notebooks);
    recordingsOfNotebooks.addAll(revival.notebooks);
    outlineOfNotebooks.addAll(revival.notebooks);
    revival.surfaces.forEach(_manyChanged);
    undoneNotebooks.addAll(revival.undoneNotebooks);
    _addPages(revival.undonePages);
  }

  /// Page ids, not counts: a revival reported twice (a slice applied
  /// again, a pull announced again) counts each page once.
  void _addPages(Map<String, Set<String>> pages) {
    for (final MapEntry(:key, :value) in pages.entries) {
      undonePages.putIfAbsent(key, () => {}).addAll(value);
    }
  }

  /// Adds what [other] changed.
  void addAll(RemoteChanges other) {
    notebooks |= other.notebooks;
    folders |= other.folders;
    libraryWrites += other.libraryWrites;
    templates |= other.templates;
    revived |= other.revived;
    undoneNotebooks.addAll(other.undoneNotebooks);
    _addPages(other.undonePages);
    pagesOfNotebooks.addAll(other.pagesOfNotebooks);
    for (final surface in other.strokeSurfaces) {
      final ids = other.itemsOf(surface);
      if (ids == null) {
        _manyChanged(surface);
      } else {
        for (final id in ids) {
          addItem(surface, id);
        }
      }
    }
    outlineOfNotebooks.addAll(other.outlineOfNotebooks);
    recordingsOfNotebooks.addAll(other.recordingsOfNotebooks);
    versionsOfNotebooks.addAll(other.versionsOfNotebooks);
  }

  bool get isEmpty =>
      !notebooks &&
      !folders &&
      !templates &&
      pagesOfNotebooks.isEmpty &&
      strokeSurfaces.isEmpty &&
      recordingsOfNotebooks.isEmpty &&
      outlineOfNotebooks.isEmpty &&
      versionsOfNotebooks.isEmpty;
}
