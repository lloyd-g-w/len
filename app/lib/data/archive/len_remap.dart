import '../../core/clock.dart';
import '../syncable.dart';

/// Gives the records of a Len file new ids as they are imported, so the
/// import is a copy that never collides with what is here (the same file
/// imported twice gives two copies), and points their references at the
/// copies.
///
/// Folders, templates, notebooks, pages, outline entries and recordings
/// keep a mapping (others refer to them); strokes and elements just get
/// fresh ids. References to rows that are not in the file are mapped too
/// (nothing then shows them), except links to pages: those lead to the
/// copy only when the file holds the page, else stay as they are (to a
/// notebook here, or shown as deleted).
class LenRemap {
  LenRemap({required this.deviceId, required this.version, this.clock = const Clock()});

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
    final copy = {...data};
    String? ref(String field, {Set<String>? into}) {
      if (copy[field] case final String old) {
        final id = copy[field] = idOf(old);
        into?.add(id);
        return id;
      }
      return null;
    }

    final String id;
    switch (record.collection) {
      case 'folders' || 'notebooks' || 'templates':
        // Parents (folder, folder of a notebook) are set once all are known.
        id = idOf(record.id);
      case 'pages' || 'recordings':
        id = idOf(record.id);
        ref('notebookId', into: owners);
      case 'outline':
        id = idOf(record.id);
        ref('notebookId', into: owners);
        ref('pageId');
        ref('parentId');
      case 'strokes':
        id = clock.newId();
        ref('surfaceId', into: surfaces);
      case 'elements':
        id = clock.newId();
        ref('surfaceId', into: surfaces);
        _relink(copy);
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
