import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/surface_stats.dart';
import '../../ui/app_theme.dart';
import '../../ui/sync_status_button.dart';
import '../settings/settings_screen.dart';
import 'library_actions.dart';
import 'library_content.dart';
import 'library_controller.dart';
import 'library_sidebar.dart';
import 'thumbnails/thumbnail_cache.dart';
import 'thumbnails/thumbnail_renderer.dart';
import 'thumbnails/thumbnail_scope.dart';

/// Home screen: the notebook library with folders, favourites and trash.
///
/// Tablets and desktop get a sidebar; phones a bottom navigation bar.
/// Shortcuts: Ctrl+N new notebook, Ctrl+Shift+N new folder, Ctrl+F search,
/// Delete moves the focused notebook to the trash, Esc clears the search.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  AppServices? _services;
  late LibraryController _controller;
  late ThumbnailCache _thumbnails;
  late LibraryActions _actions;
  StreamSubscription<Object?>? _remoteChanges;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Library search');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services == _services) return;
    if (_services != null) _disposeServices();
    _services = services;
    _controller = LibraryController(services);
    _thumbnails = ThumbnailCache(
      renderer: ThumbnailRenderer(
        pages: services.pages,
        strokes: services.strokes,
        elements: services.elements,
      ),
      stats: SurfaceStats(services.database),
    );
    _actions = LibraryActions(controller: _controller, thumbnails: _thumbnails);
    _remoteChanges = services.sync.remoteChanges.listen((c) {
      if (c.strokeSurfaces.isNotEmpty || c.pagesOfNotebooks.isNotEmpty) _thumbnails.invalidate();
      if (c.notebooks || c.folders) _controller.reload();
    });
  }

  void _disposeServices() {
    unawaited(_remoteChanges?.cancel());
    _controller.dispose();
    _thumbnails.dispose();
  }

  @override
  void dispose() {
    _disposeServices();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSettings() => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  void _clearSearch() {
    _search.clear();
    _controller.query = '';
    _searchFocus.unfocus();
  }

  void _trashFocused() {
    final id = _controller.focusedNotebookId;
    final notebook = id == null ? null : _services!.notebooks.get(id);
    if (notebook == null || notebook.isTrashed) return;
    final focusContext = FocusManager.instance.primaryFocus?.context ?? context;
    unawaited(_actions.trash(focusContext, notebook));
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
        unawaited(_actions.createNotebook(context)),
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () =>
        unawaited(_actions.createFolder(context)),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): _focusSearch,
    const SingleActivator(LogicalKeyboardKey.delete): _trashFocused,
    const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
  };

  @override
  Widget build(BuildContext context) {
    return ThumbnailScope(
      cache: _thumbnails,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => PopScope(
          // Android back walks up folders before leaving the app.
          canPop: _controller.section == LibrarySection.library && _controller.folderId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _controller.goUp();
          },
          child: CallbackShortcuts(
            bindings: _shortcuts,
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < Breakpoints.medium
                    ? _phone(context)
                    : _wide(context, constraints.maxWidth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content({List<Widget> headerTrailing = const []}) => AnimatedSwitcher(
    duration: Motion.medium,
    switchInCurve: Motion.standard,
    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
    child: KeyedSubtree(
      key: ValueKey('${_controller.section}/${_controller.folderId}'),
      child: LibraryContent(
        actions: _actions,
        searchController: _search,
        searchFocus: _searchFocus,
        headerTrailing: headerTrailing,
      ),
    ),
  );

  /// The "New" button; hidden in the trash and when the empty state
  /// already offers one.
  Widget? _fab(BuildContext context) =>
      _controller.section == LibrarySection.trash ||
          (_controller.section == LibrarySection.library &&
              !_controller.isSearching &&
              _controller.visibleFolders.isEmpty &&
              _controller.visibleNotebooks.isEmpty &&
              _controller.folderId == null)
      ? null
      : FloatingActionButton.extended(
          onPressed: () => unawaited(_actions.createNotebook(context)),
          tooltip: 'New notebook or canvas (Ctrl+N)',
          icon: const Icon(Icons.add_rounded),
          label: const Text('New'),
        );

  Widget _wide(BuildContext context, double width) {
    return Scaffold(
      body: Row(
        children: [
          LibrarySidebar(
            actions: _actions,
            onOpenSettings: _openSettings,
            width: width >= Breakpoints.expanded ? 272 : 232,
          ),
          Expanded(child: _content()),
        ],
      ),
      floatingActionButton: _fab(context),
    );
  }

  Widget _phone(BuildContext context) {
    const sections = LibrarySection.values;
    return Scaffold(
      body: _content(
        headerTrailing: [SyncStatusButton(sync: _services!.sync, onConfigure: _openSettings)],
      ),
      floatingActionButton: _fab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: sections.indexOf(_controller.section),
        onDestinationSelected: (i) =>
            i == sections.length ? _openSettings() : _controller.showSection(sections[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: 'Favourites',
          ),
          NavigationDestination(
            icon: Icon(Icons.delete_outline_rounded),
            selectedIcon: Icon(Icons.delete_rounded),
            label: 'Trash',
          ),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
