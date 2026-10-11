import 'outline_entry.dart';

/// One visible row of an outline: the entry, its nesting depth, the index
/// of its page in the notebook (null if the page was deleted) and whether
/// it has children.
typedef OutlineTreeRow = ({OutlineEntry entry, int depth, int? page, bool hasChildren});

/// Arranges a notebook's [OutlineEntry]s as a tree (pure, unit-tested).
///
/// Siblings are ordered by their page's position (entries of deleted pages
/// last), then by creation time. An entry whose parent is missing, or that
/// is part of a parent cycle (possible after concurrent edits on two
/// devices), is shown at the top level, so nothing becomes unreachable.
class OutlineTree {
  OutlineTree(List<OutlineEntry> entries, Map<String, int> pageIndex) : _pageIndex = pageIndex {
    final byId = {for (final e in entries) e.id: e};
    for (final e in entries) {
      (_children[effectiveParentOf(e, byId)] ??= []).add(e);
    }
    for (final list in _children.values) {
      list.sort(_compare);
    }
  }

  final Map<String, int> _pageIndex;
  final Map<String?, List<OutlineEntry>> _children = {};

  int _compare(OutlineEntry a, OutlineEntry b) {
    const missing = 1 << 30;
    final c = (_pageIndex[a.pageId] ?? missing).compareTo(_pageIndex[b.pageId] ?? missing);
    if (c != 0) return c;
    final t = a.createdAt.compareTo(b.createdAt);
    return t != 0 ? t : a.id.compareTo(b.id);
  }

  /// The parent [entry] is shown under: its stored parent, or null if that
  /// is missing or the entry is part of a cycle.
  static String? effectiveParentOf(OutlineEntry entry, Map<String, OutlineEntry> byId) {
    final parent = entry.parentId;
    if (parent == null || !byId.containsKey(parent)) return null;
    String? cursor = parent;
    for (var steps = 0; cursor != null && steps <= byId.length; steps++) {
      if (cursor == entry.id) return null;
      cursor = byId[cursor]?.parentId;
    }
    return parent;
  }

  /// Children of [parentId] (null = top level), in order.
  List<OutlineEntry> childrenOf(String? parentId) => _children[parentId] ?? const [];

  /// The rows depth first, leaving out the children of [collapsed] entries.
  List<OutlineTreeRow> rows({Set<String> collapsed = const {}}) {
    final rows = <OutlineTreeRow>[];
    void visit(String? parent, int depth) {
      for (final e in childrenOf(parent)) {
        final kids = childrenOf(e.id);
        rows.add((
          entry: e,
          depth: depth,
          page: _pageIndex[e.pageId],
          hasChildren: kids.isNotEmpty,
        ));
        if (!collapsed.contains(e.id)) visit(e.id, depth + 1);
      }
    }

    visit(null, 0);
    return rows;
  }

  /// The parent [entry] gets when indented: the sibling shown before it
  /// (null if it is the first of its siblings and cannot be indented).
  String? indentTarget(OutlineEntry entry) {
    final siblings = _siblingsOf(entry);
    final i = siblings.indexWhere((e) => e.id == entry.id);
    return i > 0 ? siblings[i - 1].id : null;
  }

  /// Whether [entry] is nested under another one (and can be outdented).
  bool isNested(OutlineEntry entry) => _parentOf(entry) != null;

  /// The parent [entry] gets when outdented: its parent's parent (null =
  /// the top level).
  String? outdentTarget(OutlineEntry entry) {
    final parent = _parentOf(entry);
    final grand = parent == null ? null : _byId(parent);
    return grand == null ? null : _parentOf(grand);
  }

  List<OutlineEntry> _siblingsOf(OutlineEntry entry) => childrenOf(_parentOf(entry));

  String? _parentOf(OutlineEntry entry) {
    for (final MapEntry(:key, :value) in _children.entries) {
      if (value.any((e) => e.id == entry.id)) return key;
    }
    return null;
  }

  OutlineEntry? _byId(String id) {
    for (final list in _children.values) {
      for (final e in list) {
        if (e.id == id) return e;
      }
    }
    return null;
  }
}
