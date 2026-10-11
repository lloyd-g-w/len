import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/outline_repository.dart';
import '../../../domain/outline/outline_entry.dart';
import '../../../domain/outline/outline_tree.dart';
import '../../../sync/sync_controller.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../document/document_controller.dart';
import 'outline_entry_dialog.dart';

/// The outline of one open paged notebook: its entries arranged by the
/// document's current page order, and the edits the outline panel offers.
/// Follows page changes and outline changes brought by sync.
class NotebookOutline extends ChangeNotifier {
  NotebookOutline({
    required this.repository,
    required this.notebookId,
    required this.doc,
    required SyncController sync,
  }) {
    doc.addListener(_pagesChanged);
    _remote = sync.remoteChanges.listen((c) {
      if (c.outlineOfNotebooks.contains(notebookId)) reload();
    });
    reload();
  }

  final OutlineRepository repository;
  final String notebookId;
  final DocumentController doc;
  StreamSubscription<Object?>? _remote;

  late OutlineTree _tree;
  List<OutlineEntry> _entries = const [];
  String _pageKey = '';

  OutlineTree get tree => _tree;
  bool get isEmpty => _entries.isEmpty;

  /// Index of each page id in the notebook.
  Map<String, int> get _pageIndex => {for (final (i, p) in doc.pages.indexed) p.id: i};

  void reload() {
    _entries = repository.entriesOf(notebookId);
    _pageKey = _currentPageKey();
    _tree = OutlineTree(_entries, _pageIndex);
    notifyListeners();
  }

  String _currentPageKey() => doc.pages.map((p) => p.id).join(',');

  void _pagesChanged() {
    if (_currentPageKey() != _pageKey) reload();
  }

  /// Asks for a title (and parent) and adds the current page.
  Future<void> addCurrentPage(BuildContext context) async {
    final index = doc.currentPage;
    final page = doc.pages[index];
    final rows = _tree.rows();
    // Stay at the level of the entry just before this page.
    String? parent;
    for (final row in rows) {
      final p = row.page;
      if (p != null && p <= index) parent = row.entry.parentId;
    }
    final details = await showOutlineEntryDialog(
      context,
      title: 'Add page ${index + 1} to the outline',
      confirmLabel: 'Add',
      initialTitle: 'Page ${index + 1}',
      parents: rows,
      initialParent: parent,
    );
    if (details == null) return;
    repository.add(
      notebookId: notebookId,
      pageId: page.id,
      title: details.title,
      parentId: details.parentId,
    );
    reload();
    if (context.mounted) showMessage(context, 'Added “${details.title}” to the outline');
  }

  Future<void> rename(BuildContext context, OutlineEntry entry) async {
    final details = await showOutlineEntryDialog(
      context,
      title: 'Rename entry',
      confirmLabel: 'Rename',
      initialTitle: entry.title,
    );
    if (details == null) return;
    _update(entry.copyWith(title: details.title));
  }

  /// Nests [entry] under the sibling before it.
  void indent(OutlineEntry entry) {
    final parent = _tree.indentTarget(entry);
    if (parent != null) _update(entry.copyWith(parentId: parent));
  }

  /// Moves [entry] one level up.
  void outdent(OutlineEntry entry) {
    if (_tree.isNested(entry)) _update(entry.copyWith(parentId: _tree.outdentTarget(entry)));
  }

  /// Points [entry] at the current page.
  void moveToCurrentPage(OutlineEntry entry) =>
      _update(entry.copyWith(pageId: doc.pages[doc.currentPage].id));

  /// Deletes [entry] after asking; its children move up a level.
  Future<void> delete(BuildContext context, OutlineEntry entry) async {
    final nested = _tree.childrenOf(entry.id).isNotEmpty;
    final ok = await confirmAction(
      context,
      title: 'Delete “${entry.title}”?',
      message: nested
          ? 'The entries nested under it move up a level. The page stays.'
          : 'Only the outline entry is deleted; the page stays.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    repository.delete(entry.id);
    reload();
  }

  void _update(OutlineEntry entry) {
    repository.update(entry);
    reload();
  }

  @override
  void dispose() {
    doc.removeListener(_pagesChanged);
    unawaited(_remote?.cancel());
    super.dispose();
  }
}
