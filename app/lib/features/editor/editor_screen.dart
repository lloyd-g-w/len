import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../domain/preferences.dart';
import '../../ink/tool_settings.dart';
import '../../platform/fullscreen.dart';
import '../../ui/context_menu_keys.dart';
import '../../ui/messages.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/playback_keys.dart';
import '../documents/export/export_flow.dart';
import '../search/editor/editor_search_controller.dart';
import '../settings/keyboard_shortcuts.dart';
import '../settings/settings_screen.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/chrome_layout.dart';
import 'chrome/editor_tips.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/focus_handle.dart';
import 'chrome/gesture_hud.dart';
import 'document/document_layout.dart';
import 'editor_chrome_host.dart';
import 'editor_commands.dart';
import 'editor_gestures.dart';
import 'editor_import_target.dart';
import 'editor_layers.dart';
import 'editor_lifecycle.dart';
import 'editor_session.dart';
import 'editor_shortcuts.dart';
import 'links/link_actions.dart';
import 'shared/shared_notebooks.dart';
import 'split/split_controller.dart';
import 'split/split_view.dart';
import 'split/split_view_menu.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar_measure.dart';
import 'zoom/zoom_window_state.dart';

part 'editor_screen_actions.dart';
part 'editor_screen_host.dart';
part 'editor_screen_layout.dart';
part 'editor_screen_parts.dart';

/// Full-screen editor for a paged notebook or an infinite canvas: the
/// surface, the content tools' layer and the chrome around them.
///
/// The pieces live next to it: [EditorSession] (the engine side),
/// [EditorLayers] (what is stacked over the surface), [EditorChromeHost]
/// (toolbar, top bar and menus) and [EditorLifecycle] (app lifecycle,
/// sync, closing). This state owns them and wires them together.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.notebook, this.split, this.secondPane = false});

  final Notebook notebook;

  /// The workspace's split view, when shown in the editor workspace.
  final SplitController? split;

  /// The split view's second pane (its own view memory, no tab strip).
  final bool secondPane;

  @override
  State<EditorScreen> createState() => _EditorHostState();
}

class _EditorScreenState extends State<_EditorView> {
  late final AppServices _services = AppScope.read(context);

  /// The notebook and what this editor shares with its other editors.
  late final SharedNotebook _shared = _services.sharedNotebooks.acquire(widget.notebook)
    ..addListener(_onShared);
  Notebook get _notebook => _shared.notebook;
  late final EditorSession _session = _newSession();

  /// App lifecycle, remote changes, remembering the view, closing.
  late final EditorLifecycle _lifecycle = EditorLifecycle(
    services: _services,
    session: _session,
    secondPane: widget.secondPane,
    inWorkspace: widget.split != null,
  );

  /// This editor as the split view sees it.
  late final SplitPane? _pane = widget.split == null ? null : _newPane();
  final GlobalKey _areaKey = GlobalKey(debugLabel: 'editor area');

  final HudController _hud = HudController();

  /// Audio recording and ink replay (features/audio), shared by the
  /// notebook's editors.
  NotebookAudio get _audio => _shared.audio;

  /// One-time tips (stylus side button, hold to snap, the lasso, scribble
  /// to erase), at most one per opening.
  late final TipsController _tips = _newTips();

  /// In-notebook search, Ctrl+F (features/search).
  late final EditorSearchController _search;
  final CanvasGuard _guard = CanvasGuard();

  /// The toolbar's size, which the chrome's layout depends on.
  late final ToolbarMeasure _toolbar = ToolbarMeasure(_session);

  /// Focus mode: all chrome hidden, full screen.
  bool _focus = false;

  /// In focus mode, the puck and the way out hidden too (a two-finger long
  /// press): nothing but the page, for presenting.
  bool _presenting = false;

  void _togglePresenting() {
    if (!_focus || !mounted) return;
    setState(() => _presenting = !_presenting);
  }

  /// The tool to put back on leaving focus mode entered with the laser (F5).
  EditorTool? _toolBeforeLaser;

  /// Where the canvas context menu is open, if it is.
  EditorMenu? _menu;

  /// Counts canvas menu requests (each waits for the clipboard).
  int _menuRequests = 0;

  bool get _closing => _lifecycle.closing;

  /// Keyboard focus for the editor's shortcuts; reclaimed whenever the
  /// canvas is touched (e.g. after using the width slider).
  final FocusNode _focusNode = FocusNode(debugLabel: 'EditorScreen');

  /// Receives files opened with / shared to Len while this editor is shown.
  late final EditorImportTarget _importTarget = EditorImportTarget(
    context: context,
    session: _session,
    notebookId: widget.notebook.id,
    title: () => _notebook.title,
  );

  late final EditorScreenCommands _commands = _newCommands();

  @override
  void initState() {
    super.initState();
    _session.gestures
      ..onMultiFingerTap = _onMultiFingerTap
      ..onContextMenu = _openMenu
      ..onTwoFingerHold = _togglePresenting;
    _lifecycle.start();
    // Created now: it takes a result the library asked to show.
    _search = EditorSearchController.forSession(_services, _session, notebookId: _notebook.id);
    _services.openNotebooks.addListener(_onTabs);
    _services.preferences.addListener(_onPreferences);
    _audio.onNotice = _onAudioNotice;
    _session.input.events
      ..scribbleMissed = _onScribbleMissed
      ..shapeDrawn = _tips.wantsShapes ? _onShapeDrawn : null;
    _services.incomingFiles.targets.add(_importTarget);
    // Of two editors (split view), files go to the one used last.
    _focusNode.addListener(_onFocus);
    attachPdfLinks(context, _session);
    if (_pane case final pane?) widget.split!.attach(pane);
    // Take the keyboard even when another editor (the previous tab) still
    // held it while this one was built; autofocus would not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    // A text box still being typed is committed while the split view
    // still mirrors this editor's edits into the other pane, and focus
    // mode puts back the tool (shared, with linked tools) before the view
    // is saved.
    if (!_closing) _session.content.text.end(); // Counts as an edit below.
    if (_focus) _setFocus(false, disposing: true); // (`detach` shows the other pane.)
    if (_pane case final pane?) widget.split!.detach(pane);
    _focusNode.removeListener(_onFocus);
    _services.incomingFiles.targets.remove(_importTarget);
    _services.routeOwners.forget(this);
    _services.openNotebooks.removeListener(_onTabs);
    _lifecycle.dispose();
    _services.preferences.removeListener(_onPreferences);
    final edited = _session.edited;
    _search.dispose();
    if (_audio.onNotice == _onAudioNotice) _audio.onNotice = null;
    _session.dispose(); // Commits a text box still being edited.
    _shared.removeListener(_onShared);
    // The last editor of the notebook disposes what they shared (and
    // saves a running recording).
    _services.sharedNotebooks.release(_shared);
    _lifecycle.finish(edited: edited);
    _hud.dispose();
    _tips.dispose();
    _toolbar.dispose();
    _guard.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Whether the split view parked this editor (alive, not shown).
  bool _parked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parked = SplitView.parkedOf(context);
    if (parked == _parked) return;
    _parked = parked;
    // A parked pane takes no files; shown again, it takes them when used.
    if (parked) _services.incomingFiles.targets.remove(_importTarget);
  }

  void _onTabs() {
    if (mounted) setState(() {}); // The tab strip may appear or go.
  }

  void _onAudioNotice(String message) {
    if (mounted) showMessage(context, message);
  }

  /// The notebook changed (in another editor or on another device), or
  /// was deleted on another device.
  void _onShared() {
    if (!mounted || _closing) return;
    if (_shared.gone case final gone?) {
      final pane = _pane;
      _lifecycle.closeDeleted(
        context,
        trashed: gone == NotebookGone.trashed,
        owner: this,
        // The second pane goes: say why in the first.
        announce: pane != null && pane.secondary
            ? (message) => widget.split!.messageOther(pane, message)
            : null,
      );
    } else {
      setState(() {});
    }
  }

  void _onFocus() {
    if (!_focusNode.hasFocus) return;
    if (_pane case final pane?) widget.split!.use(pane);
    _services.incomingFiles.targets.add(_importTarget);
    _services.routeOwners.current = this; // Dialogs opened by keyboard.
  }

  /// Toolbar placement, stylus-only, the side button and the writing
  /// gestures changed elsewhere (e.g. in the settings opened from the
  /// editor).
  void _onPreferences() {
    if (!mounted) return;
    final prefs = _services.preferences;
    final stylusOnly = prefs.stylusOnly;
    if (stylusOnly != _session.tools.stylusOnly) _session.tools.stylusOnly = stylusOnly;
    _session.tools
      ..penButtonErases = prefs.penButtonAction == PenButtonAction.eraser
      ..holdToStraighten = prefs.holdToSnap
      ..scribbleToErase = prefs.scribbleToErase;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Events

  /// Opens the canvas menu at [at] once the system clipboard said whether
  /// there is something to paste (the latest request wins).
  Future<void> _openMenu(Offset at) async {
    if (!mounted || _closing) return;
    final request = ++_menuRequests;
    final menu = await canvasMenuAt(context, _session, at, onFollowLink: _followLink);
    if (!mounted || _closing || request != _menuRequests) return;
    if (menu != null) setState(() => _menu = menu);
  }

  void _closeMenu() {
    _menuRequests++; // A menu still asking the clipboard stays shut.
    if (_menu == null) return;
    // Opened from the keyboard: focus goes back to the page.
    final inMenu = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<CanvasContextMenu>();
    setState(() => _menu = null);
    if (inMenu != null) _focusNode.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Commands

  /// Focus mode: no chrome, full screen (immersive on Android), this pane
  /// alone in the split view. Leaving it puts back the tool the laser
  /// replaced (F5).
  void _setFocus(bool on, {bool disposing = false}) {
    if (on == _focus) return;
    _focus = on;
    _presenting = false;
    if (!on) {
      final tool = _toolBeforeLaser;
      _toolBeforeLaser = null;
      if (tool != null && _session.tools.tool == EditorTool.laser) _session.tools.tool = tool;
      if (!disposing) _session.unparkZoomWindow();
    }
    setImmersive(on);
    unawaited(setFullscreen(on));
    if (disposing) return;
    if (_pane case final pane?) widget.split!.solo(on ? pane : null);
    if (on) _focusNode.requestFocus();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final open = _services.openNotebooks;
    final tabs = open.contains(_notebook.id) && !widget.secondPane ? open : null;
    // The second pane's bar lines up with the first's tab strip.
    final primaryWidth = widget.secondPane ? SplitView.primaryWidthOf(context) : null;
    final band =
        primaryWidth != null &&
        EditorTopBar.showsStrip(Size(primaryWidth, MediaQuery.sizeOf(context).height), open);
    // Back (e.g. Android's) leaves focus mode before leaving the editor.
    return PopScope(
      canPop: !_focus,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setFocus(false);
      },
      child: Scaffold(
        body: CallbackShortcuts(
          bindings: _shortcuts(tabs),
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            // Where the toolbar docks depends on its width (the slot counts);
            // other tool changes never rebuild the editor (the toolbar's
            // parts listen to the tools themselves).
            child: ListenableBuilder(
              listenable: _toolbar,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) => _buildArea(context, constraints, tabs, band),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
