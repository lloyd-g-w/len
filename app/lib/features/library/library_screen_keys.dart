part of 'library_screen.dart';

/// The library's keyboard shortcuts and what they do.
extension _LibraryKeys on _LibraryScreenState {
  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  void _clearSearch() {
    if (_actions.selection.active) {
      _actions.selection.clear();
      return;
    }
    _search.clear();
    _controller.query = '';
    _searchFocus.unfocus();
  }

  /// Ctrl+A: selects every notebook shown (a focused text field keeps its
  /// own Ctrl+A).
  void _selectAll() {
    final ids = [for (final n in _controller.visibleNotebooks) n.id];
    if (ids.isNotEmpty) _actions.selection.selectAll(ids);
  }

  void _trashFocused() {
    if (_actions.selection.active && _controller.section != LibrarySection.trash) {
      _actions.trashSelected(context, _actions.selection);
      return;
    }
    final id = _controller.focusedNotebookId;
    final notebook = id == null ? null : _services!.notebooks.get(id);
    if (notebook == null || notebook.isTrashed) return;
    final focusContext = FocusManager.instance.primaryFocus?.context ?? context;
    unawaited(_actions.trash(focusContext, notebook));
  }

  /// The notebook with keyboard focus, if it is not in the trash.
  Notebook? get _focusedNotebook {
    final id = _controller.focusedNotebookId;
    final notebook = id == null ? null : _services!.notebooks.get(id);
    return notebook == null || notebook.isTrashed ? null : notebook;
  }

  void _renameFocused() {
    final notebook = _focusedNotebook;
    if (notebook == null) return;
    final focusContext = FocusManager.instance.primaryFocus?.context ?? context;
    unawaited(_actions.onNotebookAction(focusContext, notebook, NotebookAction.rename));
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    // Ctrl, and ⌘ on Apple keyboards.
    for (final mod in [(control: true, meta: false), (control: false, meta: true)]) ...{
      SingleActivator(LogicalKeyboardKey.keyN, control: mod.control, meta: mod.meta): () =>
          unawaited(_actions.createNotebook(context)),
      SingleActivator(
        LogicalKeyboardKey.keyN,
        control: mod.control,
        meta: mod.meta,
        shift: true,
      ): () =>
          unawaited(_actions.createFolder(context)),
      SingleActivator(LogicalKeyboardKey.keyF, control: mod.control, meta: mod.meta): _focusSearch,
    },
    ...keyboardShortcutsBinding(() => unawaited(showKeyboardShortcuts(context))),
    const SingleActivator(LogicalKeyboardKey.delete): _trashFocused,
    const SingleActivator(LogicalKeyboardKey.backspace, meta: true): _trashFocused,
    const SingleActivator(LogicalKeyboardKey.f2): _renameFocused,
    const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
    const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
    const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
  };
}
