import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../core/startup_trace.dart';
import '../../data/surface_stats.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../audio/ui/recover_recording_dialog.dart';
import '../camera/lost_photo_flow.dart';
import '../documents/import/import_flow.dart';
import '../settings/keyboard_shortcuts.dart';
import '../settings/settings_screen.dart';
import 'library_actions.dart';
import 'library_content.dart';
import 'library_controller.dart';
import 'library_file_drop.dart';
import 'library_menus.dart';
import 'library_new_menu.dart';
import 'library_notice.dart';
import 'library_search_field.dart';
import 'library_sidebar.dart';
import 'selection/selection_actions.dart';
import 'selection/selection_bar.dart';
import 'thumbnails/thumbnail_cache.dart';
import 'thumbnails/thumbnail_renderer.dart';
import 'thumbnails/thumbnail_scope.dart';

part 'library_screen_keys.dart';
part 'library_screen_layout.dart';

/// Home screen: the notebook library with folders, favourites and trash.
///
/// From [Breakpoints.medium] a sidebar (unless the window is short, a
/// phone held sideways); below it the same content in a drawer (☰). Shortcuts: Ctrl+N new notebook, Ctrl+Shift+N new folder,
/// Ctrl+F search, Ctrl+A select all, Delete (⌘⌫ on Macs) moves the focused
/// (or selected) notebooks to the trash, F2 renames the focused notebook,
/// Esc ends selection or clears the search. Ctrl- and Shift-click select
/// notebooks.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.restored});

  /// The editor launched over the library ([launchRoutes]), if any.
  final Route<void>? restored;

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

  /// Notices from sync (e.g. everything was synced again), shown once.
  StreamSubscription<Object?>? _syncNotices;
  final _search = TextEditingController();
  final _searchFocus = LibrarySearchFocus();

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
      // Opening a folder ends the search: the field follows.
      if (_controller.query.isEmpty && _search.text.isNotEmpty) _search.clear();
    });
    _imports = ImportFlow(
      services: services,
      adopt: _controller.adoptNotebook,
      show: _showImported,
    );
    services.incomingFiles.handler = (files) => unawaited(_imports.enqueue(context, files));
    services.incomingFiles.syncSetup.addListener(_onSyncSetup);
    // Len files imported anywhere (Settings → Restore, "Open with").
    services.lenFiles.addListener(_onLenImport);
    // Len files of notebooks and folders go into the open folder, wherever
    // the import started (UX_AUDIT R8-15).
    services.lenFiles.openFolder = () =>
        _controller.section == LibrarySection.library ? _controller.folderId : null;
    // A recording or a camera photo cut off by the app being killed:
    // offer to recover it, carry on with it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTrace.mark('library');
      if (!mounted) return;
      unawaited(_resumeLostPhoto(services, editorUp: widget.restored != null));
      unawaited(offerRecordingRecovery(context, services));
      _onSyncSetup(); // Launched with a setup link.
    });
    // Back from the editor launched over the library: as after
    // [LibraryActions.openNotebook].
    widget.restored?.popped.then((_) {
      if (!mounted) return;
      _thumbnails.invalidate(services.openNotebooks.takeVisited());
      _controller.reload();
    });
    _remoteChanges = services.sync.remoteChanges.listen((c) {
      if (c.strokeSurfaces.isNotEmpty || c.pagesOfNotebooks.isNotEmpty) _thumbnails.invalidate();
      if (c.notebooks || c.folders) _controller.reload();
    });
    _syncNotices = services.sync.notices.listen((notice) {
      if (mounted) showMessage(context, notice);
    });
  }

  /// Android killed Len while the camera app was in front: the photo
  /// taken goes where it was meant to ([resumeLostPhoto]). [editorUp]:
  /// the workspace is being reopened.
  Future<void> _resumeLostPhoto(AppServices services, {required bool editorUp}) => resumeLostPhoto(
    context,
    services,
    LostPhotoHost(
      scanNew: (photos) => _actions.scanDocument(context, photos: photos),
      show: (notebook) {
        if (editorUp || services.incomingFiles.targets.active != null) {
          services.openNotebooks.open(notebook); // The editor shows its tab.
        } else {
          unawaited(_actions.openNotebook(context, notebook));
        }
      },
      importFiles: (photos) => _imports.enqueue(context, photos),
    ),
  );

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

  /// A sync setup link opened with Len: Settings → Sync fills its form
  /// with it, opened here unless it is shown already (and took the link).
  void _onSyncSetup() => scheduleMicrotask(() {
    if (mounted && _services?.incomingFiles.syncSetup.value != null) _openSettings(sync: true);
  });

  void _onLenImport() => _controller.reload();

  void _disposeServices() {
    _services?.incomingFiles.syncSetup.removeListener(_onSyncSetup);
    _services?.incomingFiles.handler = null;
    _services?.lenFiles.removeListener(_onLenImport);
    _services?.lenFiles.openFolder = () => null;
    unawaited(_remoteChanges?.cancel());
    unawaited(_syncNotices?.cancel());
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

  @override
  Widget build(BuildContext context) {
    return ThumbnailScope(
      cache: _thumbnails,
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _actions.selection]),
        builder: (context, _) => PopScope(
          // Android back ends selection, then the search, then walks up
          // folders, then leaves.
          canPop:
              !_actions.selection.active &&
              _controller.query.isEmpty &&
              _controller.section == LibrarySection.library &&
              _controller.folderId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_actions.selection.active) {
              _actions.selection.clear();
            } else if (_controller.query.isNotEmpty) {
              _clearSearch();
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
                  builder: (context, constraints) => Breakpoints.libraryCompact(constraints.biggest)
                      ? _phone(context)
                      : _wide(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
