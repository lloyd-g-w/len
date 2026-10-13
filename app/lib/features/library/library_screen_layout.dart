part of 'library_screen.dart';

/// The library's layouts: a sidebar on wide screens, a drawer, a FAB and
/// a bottom selection bar on phones.
extension _LibraryLayout on _LibraryScreenState {
  Widget _content({Widget? headerLeading}) => LibraryNotices(
    child: AnimatedSwitcher(
      duration: Motion.medium,
      switchInCurve: Motion.standard,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey('${_controller.section}/${_controller.folderId}'),
        child: LibraryContent(
          actions: _actions,
          searchController: _search,
          searchFocus: _searchFocus,
          headerLeading: headerLeading,
        ),
      ),
    ),
  );

  /// The "New" button (phones only: wide screens have the "New…" tile and
  /// ⊕▾). Like ⊕▾ it belongs to the library and its folders, so it hides in
  /// favourites, the trash, search and selection, and when the empty state
  /// already offers to create one.
  Widget? _fab(BuildContext context) =>
      _actions.selection.active ||
          _controller.section != LibrarySection.library ||
          _controller.isSearching ||
          (_controller.visibleFolders.isEmpty && _controller.visibleNotebooks.isEmpty)
      ? null
      // Tap: a new notebook. Long press: everything ⊕▾ offers on wide
      // screens (a canvas, a PDF, a folder), which phones have no room for.
      : Semantics(
          onLongPressHint: 'More: canvas, PDF, folder',
          child: GestureDetector(
            onLongPress: () async {
              final choice = await showContextMenuAt<NewChoice>(context, items: newMenuItems());
              if (choice != null && context.mounted) {
                unawaited(runNewChoice(context, _actions, choice));
              }
            },
            child: Tooltip(
              message: 'New notebook',
              // A touch long press opens the menu, not the tooltip.
              triggerMode: TooltipTriggerMode.manual,
              child: FloatingActionButton(
                onPressed: () => unawaited(_actions.createNotebook(context)),
                child: const Icon(Symbols.add_sharp, semanticLabel: 'New notebook'),
              ),
            ),
          ),
        );

  Widget _wide(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          LibrarySidebar(
            actions: _actions,
            onOpenSettings: _openSettings,
            onOpenSyncSettings: () => _openSettings(sync: true),
          ),
          Expanded(
            // The selection bar floats over the content, not the sidebar.
            child: Stack(
              children: [
                Positioned.fill(child: MessagePane(child: _content())),
                if (_selectionBar() case final bar?)
                  Positioned(left: 0, right: 0, bottom: 0, child: bar),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _selectionBar() => _actions.selection.active
      ? LibrarySelectionBar(actions: _actions, selection: _actions.selection)
      : null;

  /// Phones: the sidebar's content in a drawer, opened from ☰.
  Widget _phone(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        width: 288,
        child: Builder(
          builder: (context) => LibrarySidebar(
            actions: _actions,
            width: 288,
            onNavigate: Navigator.of(context).pop,
            onOpenSettings: () {
              Navigator.of(context).pop();
              _openSettings();
            },
            onOpenSyncSettings: () {
              Navigator.of(context).pop();
              _openSettings(sync: true);
            },
          ),
        ),
      ),
      body: _content(
        headerLeading: Builder(
          builder: (context) => ListenableBuilder(
            listenable: _services!.sync,
            // A dot while sync fails: the status is in the drawer.
            builder: (context, _) {
              final failing = _services!.sync.state == SyncState.error;
              return IconButton(
                tooltip: failing ? 'Menu (sync failed)' : 'Menu',
                icon: Badge(
                  isLabelVisible: failing,
                  smallSize: 8,
                  child: const Icon(Symbols.menu_sharp),
                ),
                onPressed: Scaffold.of(context).openDrawer,
              );
            },
          ),
        ),
      ),
      floatingActionButton: _fab(context),
      bottomNavigationBar: _selectionBar(),
    );
  }
}
