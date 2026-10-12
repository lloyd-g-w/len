import 'package:flutter/foundation.dart';

/// Notebooks picked in the library's selection mode (GoodNotes' "Select"):
/// null outside selection mode, else the selected notebook ids.
class LibrarySelection extends ChangeNotifier {
  Set<String>? _ids;

  /// Where a Shift-click range starts: the notebook toggled last.
  String? _anchor;

  /// Whether selection mode is on.
  bool get active => _ids != null;

  /// Selected notebook ids (empty outside selection mode).
  Set<String> get ids => _ids ?? const {};

  int get count => ids.length;

  bool contains(String id) => ids.contains(id);

  /// Turns selection mode on, optionally with [id] selected.
  void start([String? id]) {
    _ids = {?id};
    notifyListeners();
  }

  /// Selects or deselects [id] (starting selection mode if needed).
  void toggle(String id) {
    final ids = _ids ??= {};
    if (!ids.remove(id)) ids.add(id);
    _anchor = id;
    notifyListeners();
  }

  /// Adds the notebooks from the last toggled one to [id] in [ordered]
  /// (the library's order) to the selection; just toggles [id] without an
  /// anchor.
  void extendTo(String id, List<String> ordered) {
    final from = _anchor == null ? -1 : ordered.indexOf(_anchor!);
    final to = ordered.indexOf(id);
    if (from < 0 || to < 0) return toggle(id);
    final (a, b) = from <= to ? (from, to) : (to, from);
    (_ids ??= {}).addAll(ordered.sublist(a, b + 1));
    notifyListeners();
  }

  /// Selects exactly [ids].
  void selectAll(Iterable<String> ids) {
    _ids = {...ids};
    notifyListeners();
  }

  /// Keeps only ids still in [visible] (after a reload).
  void retain(Iterable<String> visible) {
    final ids = _ids;
    if (ids == null) return;
    final keep = visible.toSet();
    final before = ids.length;
    ids.removeWhere((id) => !keep.contains(id));
    if (ids.length != before) notifyListeners();
  }

  /// Leaves selection mode.
  void clear() {
    if (_ids == null) return;
    _ids = null;
    _anchor = null;
    notifyListeners();
  }
}
