part of 'library_content.dart';

/// The notebooks of the library's main area: captions, the grid of cards
/// and the list of rows.
extension _LibraryItems on _LibraryContentState {
  /// The caption under a notebook's title; [list] rows have room to name
  /// its recordings too ("Saturday, 3 pages, 2 recordings"; cards show a
  /// mic glyph instead).
  String _subtitle(Notebook n, {bool list = false}) {
    if (n.isTrashed) return trashLeftLabel(n.trashedAt!, NotebookRepository.trashKeptFor);
    if (_c.isSearching) {
      // Found by a recording: say which ("Recording “Lecture 4”").
      if (_c.recordingMatchOf(n) case final title?) return 'Recording “$title”';
      return _c.locationOf(n);
    }
    final kind = n.kind == NotebookKind.canvas ? 'canvas' : pageCountLabel(_c.pageCountOf(n.id));
    final date = _c.sort == LibrarySort.created
        ? libraryDateAfter('Created', n.createdAt)
        : formatLibraryDate(n.editedAt);
    final recordings = _c.recordingCountOf(n.id);
    // Commas, not a `·` chain (DESIGN §2): "Saturday, 3 pages".
    return [
      date,
      kind,
      if (list && recordings > 0) recordings == 1 ? '1 recording' : '$recordings recordings',
    ].join(', ');
  }

  Widget _grid(
    BuildContext context,
    List<Notebook> notebooks,
    bool compact, {
    required bool newTile,
  }) {
    final offset = newTile ? 1 : 0;
    return SliverGrid.builder(
      // Columns from the width in the delegate, not a layout builder: a
      // builder above the grid would rebuild every card on every scroll frame.
      gridDelegate: CoverGridDelegate(
        coverWidth: LibraryContent.coverWidth,
        spacing: LibraryContent.gridSpacingFor(compact: compact),
        captionHeight: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
      ),
      itemCount: notebooks.length + offset,
      findChildIndexCallback: _indexOf(notebooks, offset: offset),
      itemBuilder: (context, i) {
        if (i < offset) {
          return NewNotebookTile(
            key: const ValueKey('new-notebook-tile'),
            onPressed: () => unawaited(actions.createNotebook(context)),
          );
        }
        final notebook = notebooks[i - offset];
        final subtitle = _subtitle(notebook);
        final recordings = notebook.isTrashed ? 0 : _c.recordingCountOf(notebook.id);
        final selection = actions.selection;
        return _keep(
          'card/${notebook.id}',
          (
            notebook,
            subtitle,
            recordings,
            actions,
            selection.active,
            selection.contains(notebook.id),
          ),
          () => NotebookCard(
            key: ValueKey(notebook.id),
            notebook: notebook,
            subtitle: subtitle,
            recordings: recordings,
            actions: actions,
          ),
        );
      },
    );
  }

  /// Where the card or row keyed by a notebook's id now is: after a sort,
  /// a move or a reload, cards on screen keep their state (and cover)
  /// instead of being built anew.
  static int? Function(Key) _indexOf(List<Notebook> notebooks, {int offset = 0}) {
    Map<String, int>? index;
    return (key) {
      if (key is! ValueKey<String>) return null;
      index ??= {for (var i = 0; i < notebooks.length; i++) notebooks[i].id: i + offset};
      return index![key.value];
    };
  }

  /// The list view's widest rows: the star and ⋯ stay near the titles.
  static const double listMaxWidth = 960;

  Widget _list(List<Notebook> notebooks) {
    return SliverConstrainedCrossAxis(maxExtent: listMaxWidth, sliver: _listRows(notebooks));
  }

  Widget _listRows(List<Notebook> notebooks) {
    final indexOf = _indexOf(notebooks);
    return SliverList.separated(
      itemCount: notebooks.length,
      findItemIndexCallback: indexOf,
      // Rows are ruled like the folder row: a hairline that starts at
      // the titles.
      separatorBuilder: (context, _) => Divider(
        height: Hairline.width,
        indent: NotebookListTile.textInset,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      itemBuilder: (context, i) {
        final notebook = notebooks[i];
        final subtitle = _subtitle(notebook, list: true);
        final selection = actions.selection;
        return _keep(
          'row/${notebook.id}',
          (notebook, subtitle, actions, selection.active, selection.contains(notebook.id)),
          () => NotebookListTile(
            key: ValueKey(notebook.id),
            notebook: notebook,
            subtitle: subtitle,
            actions: actions,
          ),
        );
      },
    );
  }
}
