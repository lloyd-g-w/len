import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../domain/preferences.dart';
import '../../ink/tool_settings.dart';
import '../../platform/fullscreen.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_picker/eyedropper_scope.dart';
import '../../ui/context_menu_keys.dart';
import '../../ui/messages.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/playback_keys.dart';
import '../audio/ui/recordings_sheet.dart';
import '../documents/export/export_flow.dart';
import '../documents/export/print_flow.dart';
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
import 'eyedropper/eyedropper.dart';
import 'eyedropper/page_colours.dart';
import 'links/link_actions.dart';
import 'resume_view.dart';
import 'shared/shared_notebooks.dart';
import 'sidebar/page_sidebar.dart';
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
part 'editor_screen_wiring.dart';

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

  /// The surface's repaint boundary (the eyedropper's loupe shows it).
  final GlobalKey _canvasKey = GlobalKey(debugLabel: 'editor canvas');

  /// "Pick from page" for the colour pickers opened from this editor.
  late final Eyedropper _eyedropper = Eyedropper(
    colours: PageColours(session: _session, canvas: _canvasKey, area: _areaKey),
    addRecent: _session.tools.addRecentColor,
  );

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

  /// Whether this notebook keeps its pages beside the page (remembered per
  /// notebook; shown where the pane has room, not in focus mode).
  late bool _sidebar = _session.doc != null && _services.settings.pageSidebar(widget.notebook.id);

  /// The pane's size, as last laid out.
  Size _paneSize = Size.zero;

  /// Whether the pane has room for the page sidebar.
  bool get _sidebarFits => _session.doc != null && SidebarMetrics.fits(_paneSize);

  /// Shows or hides the pages beside the page, and remembers it.
  void _setSidebar(bool open) {
    if (!mounted || _session.doc == null) return;
    if (open && !_sidebarFits) {
      showMessage(context, 'No room for pages beside the page here');
      return;
    }
    _services.settings.setPageSidebar(_notebook.id, open);
    setState(() => _sidebar = open);
  }

  /// F4: the pages beside the page, on or off (not in focus mode).
  void _toggleSidebar() {
    if (!_focus) _setSidebar(!(_sidebar && _sidebarFits));
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
    _start();
  }

  @override
  void dispose() {
    _stop();
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
    // Gone to reading while parked: the reading tip now it shows.
    if (!parked && _session.tools.reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_parked && _session.tools.reading) _onReading();
      });
    }
  }

  void _onTabs() {
    if (!mounted) return;
    setState(() {}); // The tab strip may appear or go.
    _showRecordingsIfAsked();
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
    if (_focusNode.hasFocus) _use();
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
  Widget build(BuildContext context) => _buildScreen(context);
}
