import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/surface_stats.dart';
import '../../domain/notebook.dart';
import '../../sync/sync_controller.dart';
import '../../ui/app_theme.dart';
import '../audio/ui/recover_recording_dialog.dart';
import '../documents/import/import_flow.dart';
import '../settings/keyboard_shortcuts.dart';
import '../settings/settings_screen.dart';
import 'library_actions.dart';
import 'library_content.dart';
import 'library_controller.dart';
import 'library_file_drop.dart';
import 'library_header.dart';
import 'library_menus.dart';
import 'library_notice.dart';
import 'library_sidebar.dart';
import 'selection/selection_actions.dart';
import 'selection/selection_bar.dart';
import 'thumbnails/thumbnail_cache.dart';
import 'thumbnails/thumbnail_renderer.dart';
import 'thumbnails/thumbnail_scope.dart';

/// Home screen: the notebook library with folders, favourites and trash.
///
/// From [Breakpoints.medium] a sidebar; below it the same content in a
/// drawer (☰). Shortcuts: Ctrl+N new notebook, Ctrl+Shift+N new folder,
/// Ctrl+F search, Ctrl+A select all, Delete (⌘⌫ on Macs) moves the focused
/// (or selected) notebooks to the trash, F2 renames the focused notebook,
/// Esc ends selection or clears the search. Ctrl- and Shift-click select
/// notebooks.
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

  /// Files opened with / shared to Len, and dropped onto the library.
  late ImportFlow _imports;
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
        images: services.images,
      ),
      stats: SurfaceStats(services.database),
    );
    _actions = LibraryActions(controller: _controller, thumbnails: _thumbnails);
    _scope = _scopeKey;
    // Selection belongs to one place: leaving it ends selection mode, and
    // notebooks that disappear (trashed, moved by sync, filtered out by
    // the search) are deselected. Searching stays in the place: what is
    // selected and still matches stays selected (UX_AUDIT #20).
    _controller.addListener(() {
      final scope = _scopeKey;
      if (scope != _scope) {
        _scope = scope;
        _actions.selection.clear();
      } else {
        _actions.selection.retain(_controller.visibleNotebooks.map((n) => n.id));
      }
    });
    _imports = ImportFlow(
      services: services,
      adopt: _controller.adoptNotebook,
      show: _showImported,
    );
    services.incomingFiles.handler = (files) => unawaited(_imports.enqueue(context, files));
    // A recording cut off by the app being killed: offer to recover it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(offerRecordingRecovery(context, services));
    });
    _remoteChanges = services.sync.remoteChanges.listen((c) {
      if (c.strokeSurfaces.isNotEmpty || c.pagesOfNotebooks.isNotEmpty) _thumbnails.invalidate();
      if (c.notebooks || c.folders) _controller.reload();
    });
  }

  /// Where the library is: section and folder (not the search, which only
  /// narrows what is shown).
  String get _scopeKey => '${_controller.section}/${_controller.folderId}';
  String _scope = '';

  /// Opens imported notebooks in editor tabs, the last one shown.
  void _showImported(List<Notebook> notebooks) {
    final services = _services!;
    final tabs = services.openNotebooks;
    // An editor is shown over the library: just switch its tabs.
    final editorShown = services.incomingFiles.targets.active != null;
    for (final notebook in editorShown ? notebooks : notebooks.take(notebooks.length - 1)) {
      tabs.open(notebook);
    }
    if (!editorShown) unawaited(_actions.openNotebook(context, notebooks.last));
  }

  void _disposeServices() {
    _services?.incomingFiles.handler = null;
    unawaited(_remoteChanges?.cancel());
    _actions.selection.dispose();
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

  void _openSettings({bool sync = false}) => unawaited(
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(showSync: sync))),
  );

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

  @override
  Widget build(BuildContext context) {
    return ThumbnailScope(
      cache: _thumbnails,
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _actions.selection]),
        builder: (context, _) => PopScope(
          // Android back ends selection, then walks up folders, then leaves.
          canPop:
              !_actions.selection.active &&
              _controller.section == LibrarySection.library &&
              _controller.folderId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_actions.selection.active) {
              _actions.selection.clear();
            } else {
              _controller.goUp();
            }
          },
          child: CallbackShortcuts(
            bindings: _shortcuts,
            child: Focus(
              autofocus: true,
              child: LibraryFileDrop(
                onFiles: (files) => unawaited(_imports.enqueue(context, files, offerInsert: false)),
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth < Breakpoints.medium ? _phone(context) : _wide(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
  /// ⊕▾); hidden in the trash and when the empty state already offers one
  /// (library and folders).
  Widget? _fab(BuildContext context) =>
      _actions.selection.active ||
          _controller.section == LibrarySection.trash ||
          (_controller.section == LibrarySection.library &&
              !_controller.isSearching &&
              _controller.visibleFolders.isEmpty &&
              _controller.visibleNotebooks.isEmpty)
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
                child: const Icon(Symbols.add_rounded),
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
                Positioned.fill(child: _content()),
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
                  child: const Icon(Symbols.menu_rounded),
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
