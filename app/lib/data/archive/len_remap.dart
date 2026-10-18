import '../../core/clock.dart';
import '../../domain/shape_ids.dart';
import '../syncable.dart';

/// Gives the records of a Len file new ids as they are imported, so the
/// import is a copy that never collides with what is here (the same file
/// imported twice gives two copies), and points their references at the
/// copies.
///
/// Folders, templates, notebooks, pages, outline entries and recordings
/// keep a mapping (others refer to them), and so do shapes (connectors
/// name them, [ShapeIds]: an imported arrow attaches to the imported box)
/// and text boxes (the boxes flowing on from them name them, `TextFlow`);
/// other strokes and elements just get fresh ids. References to rows that are not in the file are mapped too
/// (nothing then shows them), except links to pages: those lead to the
/// copy only when the file holds the page, else stay as they are (to a
/// notebook here, or shown as deleted).
///
/// A restored backup (UX_AUDIT R8-16) keeps the ids of the folders and
/// notebooks in [keep] (with everything in them): those not here, so a
/// second restore can tell they are here already. Notebooks in [skip]
/// are left out with everything in them. Pages, outline entries and
/// recordings of no notebook in the file, and content on no page or canvas
/// in it, are left out too (notebooks come first, then pages).
class LenRemap {
  LenRemap({
    required this.deviceId,
    required this.version,
    this.clock = const Clock(),
    Set<String> keep = const {},
    this.skip = const {},
  }) {
    for (final id in keep) {
      _ids[id] = id;
    }
  }

  /// Notebooks left out, with their pages and content.
  final Set<String> skip;

  /// The notebooks seen so far (skipped ones too).
  final Set<String> _notebooks = {};

  /// The notebook of each page seen so far, for the content on it.
  final Map<String, String> _notebookOf = {};

  /// Stamped on every imported record.
  final String deviceId;

  /// The `updatedAt` of every imported record.
  final int version;
  final Clock clock;

  final Map<String, String> _ids = {};

  /// New ids of the surfaces content was written to (pages and canvases).
  final Set<String> surfaces = {};

  /// New ids of the notebooks pages, outline entries and recordings belong to.
  final Set<String> owners = {};

  /// The new id for [old] (the same each time).
  String idOf(String old) => _ids.putIfAbsent(old, clock.newId);

  /// Whether [old] was given a new id already.
  bool knows(String old) => _ids.containsKey(old);

  /// [record] with new ids and references, stamped as a local write; null
  /// for tombstones and collections Len files don't hold. Fields of the
  /// wrong type are left for the table's parser to refuse.
  SyncRecord? remap(SyncRecord record) {
    final data = record.data;
    if (record.deleted || data == null) return null;
    // The notebook a record belongs to (a canvas is its own surface).
    final notebook = switch (record.collection) {
      'notebooks' => record.id,
      'pages' || 'recordings' || 'outline' => data['notebookId'],
      'strokes' || 'elements' => _notebookOf[data['surfaceId']] ?? data['surfaceId'],
      _ => null,
    };
    // What belongs to no notebook or page of the file is left out (it
    // would be on none here, yet synced).
    switch (record.collection) {
      case 'notebooks':
        _notebooks.add(record.id);
      case 'pages' || 'recordings' || 'outline' || 'strokes' || 'elements'
          when !_notebooks.contains(notebook):
        return null;
    }
    // Noted before a skip: the content on a skipped notebook's pages is
    // skipped with them.
    if (record.collection == 'pages' && notebook is String) _notebookOf[record.id] = notebook;
    if (skip.contains(notebook)) return null;
    // What belongs to a notebook keeping its id keeps its id too.
    final kept = notebook is String && _ids[notebook] == notebook;
    String map(String old) => kept ? _ids[old] = old : idOf(old);
    final copy = {...data};
    void ref(String field, {Set<String>? into}) {
      if (copy[field] case final String old) {
        final id = copy[field] = map(old);
        into?.add(id);
      }
    }

    final String id;
    switch (record.collection) {
      case 'folders' || 'notebooks' || 'templates' || 'notebook_styles':
        // Parents (folder, folder of a notebook) are set once all are known.
        id = idOf(record.id);
      case 'fonts':
        // Named by their file (text refers to them by it): the same font here.
        id = record.id;
      case 'pages' || 'recordings':
        id = map(record.id);
        ref('notebookId', into: owners);
      case 'outline':
        id = map(record.id);
        ref('notebookId', into: owners);
        ref('pageId');
        ref('parentId');
      case 'strokes' || 'elements':
        final style = copy['style'];
        final shape = record.collection == 'strokes' && style is Map && style['sh'] != null;
        // Text boxes are named by the boxes continuing them (`TextFlow.from`).
        final text = record.collection == 'elements' && copy['type'] == 'text';
        id = kept ? record.id : (shape || text ? idOf(record.id) : clock.newId());
        ref('surfaceId', into: surfaces);
        if (record.collection == 'elements') _relink(copy);
        if (text && !kept) _rechain(copy);
        if (shape && !kept) copy['style'] = ShapeIds.remapStyle(style, idOf) ?? style;
      default:
        return null;
    }
    return SyncRecord(
      collection: record.collection,
      id: id,
      updatedAt: version,
      deviceId: deviceId,
      deleted: false,
      data: copy,
    );
  }

  /// Points a text box flowing across pages at the copy of the box it
  /// continues (one not in the file is dropped at the end of the import,
  /// `LenImportCommit`).
  void _rechain(Map<String, Object?> element) {
    final data = element['data'];
    if (data is! Map<String, Object?>) return;
    final flow = data['flow'];
    if (flow is! Map<String, Object?>) return;
    final from = flow['from'];
    if (from is! String) return;
    element['data'] = {
      ...data,
      'flow': {...flow, 'from': idOf(from)},
    };
  }

  /// Points a link element's page target at the copy of the page, when
  /// the file holds it (notebooks and pages come before elements).
  void _relink(Map<String, Object?> element) {
    if (element['type'] != 'link') return;
    final data = element['data'];
    if (data is! Map<String, Object?>) return;
    final target = data['target'];
    if (target is! Map<String, Object?>) return;
    final notebook = target['notebook'], page = target['page'];
    if (notebook is! String || page is! String || !knows(notebook) || !knows(page)) return;
    element['data'] = {
      ...data,
      'target': {...target, 'notebook': idOf(notebook), 'page': idOf(page)},
    };
  }
}
