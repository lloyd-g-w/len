import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../sync/sync_engine.dart';
import '../../ui/text_prompt.dart';
import '../audio/audio_layer.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/audio_bar_button.dart';
import '../documents/template_picker.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import '../settings/settings_screen.dart';
import 'chrome/bar_button.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/chrome_metrics.dart';
import 'chrome/editor_chrome.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/focus_handle.dart';
import 'chrome/gesture_hud.dart';
import 'chrome/toolbar_slot.dart';
import 'document/document_layout.dart';
import 'editor_actions.dart';
import 'editor_canvas.dart';
import 'editor_gestures.dart';
import 'editor_session.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';
import 'images/image_entry_points.dart';
import 'tabs/open_notebooks.dart';

/// Full-screen editor for a paged notebook or an infinite canvas: the
/// surface, the content tools' layer and the chrome around them.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.notebook});

  final Notebook notebook;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final AppServices _services = AppScope.read(context);
  late Notebook _notebook = widget.notebook;
  late final EditorSession _session = EditorSession(
    services: _services,
    notebook: () => _notebook,
    onStylusDetected: _onStylusDetected,
    initialView: _services.openNotebooks.viewOf(widget.notebook.id),
  );
  final HudController _hud = HudController();

  /// Audio recording and ink replay (features/audio).
  late final NotebookAudio _audio = NotebookAudio(_services, notebookId: widget.notebook.id);

  /// In-notebook search, Ctrl+F (features/search).
  late final EditorSearchController _search;
  final CanvasGuard _guard = CanvasGuard();
  bool? _compact;

  /// Measured height of the toolbar panel (it wraps on narrow screens).
  final ValueNotifier<double?> _toolbarHeight = ValueNotifier(null);
  StreamSubscription<RemoteChanges>? _remoteChanges;

  /// Focus mode: all chrome hidden.
  bool _focus = false;

  /// Where the canvas context menu is open, if it is.
  ({Offset at, List<CanvasAction> actions})? _menu;

  /// Set once the editor is leaving because its notebook was deleted
  /// remotely, so further sync events don't pop another route.
  bool _closing = false;

  /// Keyboard focus for the editor's shortcuts; reclaimed whenever the
  /// canvas is touched (e.g. after using the width slider).
  final FocusNode _focusNode = FocusNode(debugLabel: 'EditorScreen');

  @override
  void initState() {
    super.initState();
    _session.gestures
      ..onMultiFingerTap = _onMultiFingerTap
      ..onContextMenu = _openMenu;
    _remoteChanges = _services.sync.remoteChanges.listen(_onRemoteChanges);
    // Created now: it takes a result the library asked to show.
    _search = EditorSearchController.forSession(_services, _session, notebookId: _notebook.id);
    _services.openNotebooks.addListener(_onTabs);
    _services.preferences.addListener(_onPreferences);
    // Take the keyboard even when another editor (the previous tab) still
    // held it while this one was built; autofocus would not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_remoteChanges?.cancel());
    _services.openNotebooks
      ..removeListener(_onTabs)
      ..saveView(_notebook.id, _session.viewState);
    _services.preferences.removeListener(_onPreferences);
    if (_focus) setImmersive(false);
    final edited = _session.edited;
    _search.dispose();
    _audio.dispose(); // Saves a running recording.
    _session.dispose(); // Commits a text box still being edited.
    if (edited) {
      _services.notebooks.touch(_notebook.id);
      // Deferred: syncing notifies listeners (e.g. the library's sync button),
      // which must not happen while the tree is locked during dispose.
      final sync = _services.sync;
      scheduleMicrotask(() => unawaited(sync.syncNow()));
    }
    _hud.dispose();
    _toolbarHeight.dispose();
    _guard.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTabs() {
    if (mounted) setState(() {}); // The tab strip may appear or go.
  }

  /// Toolbar placement, and stylus-only changed elsewhere (e.g. in the
  /// settings opened from the editor).
  void _onPreferences() {
    if (!mounted) return;
    final stylusOnly = _services.preferences.stylusOnly;
    if (stylusOnly != _session.tools.stylusOnly) _session.tools.stylusOnly = stylusOnly;
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Events

  void _onRemoteChanges(RemoteChanges changes) {
    if (!mounted || _closing) return;
    if (changes.notebooks) {
      final updated = _services.notebooks.get(_notebook.id);
      if (updated == null) {
        _closeDeleted();
        return;
      }
      setState(() => _notebook = updated);
      _services.openNotebooks.rename(updated.id, updated.title);
    }
    _session.applyRemoteChanges(changes);
  }

  /// The notebook was deleted on another device: close the editor together
  /// with anything open on top of it (dialogs, menus, sheets).
  void _closeDeleted() {
    _closing = true;
    _session.input.cancelDraw();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('“${_notebook.title}” was deleted on another device.')),
      );
    final tabs = _services.openNotebooks;
    if (tabs.contains(_notebook.id)) {
      if (route != null && route.isActive) navigator.popUntil((r) => r == route);
      tabs.close(_notebook.id); // The workspace shows another tab or leaves.
      return;
    }
    if (route == null || !route.isActive) return; // Already leaving.
    navigator
      ..popUntil((r) => r == route)
      ..pop();
  }

  void _onStylusDetected() {
    if (_session.tools.stylusOnly != null) return;
    _setStylusOnly(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Stylus detected — fingers now pan and zoom.'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _setStylusOnly(false)),
      ),
    );
  }

  void _onMultiFingerTap(int fingers) => runMultiFingerTap(_session, fingers, _hud);

  void _openMenu(Offset at) {
    if (!mounted || _closing) return;
    final doc = _session.doc;
    final actions = canvasActions(
      _session,
      at,
      bookmarked: doc?.activePageData.bookmarked ?? false,
      onPageCommand: (c) => _session.commands!.run(context, c, doc!.activePageData),
    );
    setState(() => _menu = (at: at, actions: actions));
  }

  void _closeMenu() {
    if (_menu != null) setState(() => _menu = null);
  }

  // ---------------------------------------------------------------------------
  // Commands

  void _setStylusOnly(bool value) {
    _session.tools.stylusOnly = value;
    _services.preferences.stylusOnly = value;
  }

  void _setFlow(PageFlow flow) {
    _services.settings.pageFlow = flow.name;
    _session.doc?.setFlow(flow);
  }

  void _toggleFocus() {
    setState(() => _focus = !_focus);
    setImmersive(_focus);
  }

  Future<void> _rename() async {
    final title = await showTextPrompt(
      context,
      title: 'Rename',
      initialValue: _notebook.title,
      confirmLabel: 'Rename',
    );
    if (title == null || title.isEmpty || !mounted || _closing) return;
    _update((n) => n.copyWith(title: title));
    _services.openNotebooks.rename(_notebook.id, title);
  }

  /// Changes the canvas's template and paper colour.
  Future<void> _pickBackground() async {
    final choice = await showTemplatePicker(
      context,
      initial: PageTemplate(style: _notebook.paper, color: _notebook.paperColor),
      mode: TemplatePickerMode.canvas,
    );
    if (choice == null || !mounted || _closing) return;
    final template = choice.template;
    _update((n) => n.copyWith(paper: template.style, paperColor: template.color));
  }

  void _update(Notebook Function(Notebook current) change) {
    // Re-read so a concurrent remote change isn't overwritten wholesale.
    final current = _services.notebooks.get(_notebook.id);
    if (current == null) return;
    setState(() => _notebook = _services.notebooks.update(change(current)));
  }

  void _back() => unawaited(Navigator.of(context).maybePop());

  void _openSettings() => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final tabs = _services.openNotebooks.contains(_notebook.id) ? _services.openNotebooks : null;
    // Back (e.g. Android's) leaves focus mode before leaving the editor.
    return PopScope(
      canPop: !_focus,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _focus) _toggleFocus();
      },
      child: Scaffold(
        body: CallbackShortcuts(
          bindings: {
            ...editorShortcuts(
              _session,
              toggleFocus: _toggleFocus,
              nextTab: tabs?.cycle,
              previousTab: tabs == null ? null : () => tabs.cycle(backwards: true),
              closeTab: tabs == null ? null : () => tabs.close(_notebook.id),
              paste: () => _session.images.paste(context),
            ),
            ...EditorSearchLayer.shortcuts(_search),
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            // Automatic placement depends on the toolbar's width (its slots).
            child: ListenableBuilder(
              listenable: Listenable.merge([_session.tools, _toolbarHeight]),
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final media = MediaQuery.of(context);
                  final layout = ChromeLayout(
                    placement: resolvePlacement(
                      _services.preferences.toolbarPlacement,
                      constraints.maxWidth,
                      toolbarWidth: EditorToolbar.oneRowWidth(_session.tools),
                    ),
                    toolbarHeight: _toolbarHeight.value,
                    barHeight: EditorTopBar.heightFor(constraints.maxWidth, tabs),
                    safe: media.padding,
                    hasNavigator: _session.doc != null,
                    width: constraints.maxWidth,
                    focus: _focus,
                  );
                  _applyInsets(layout.covered);
                  _resetGuardOnResize(constraints.maxWidth);
                  return CanvasGuardScope(
                    guard: _guard,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: EditorCanvas(
                            session: _session,
                            paper: _notebook.paper,
                            paperColor: _notebook.paperColor,
                            focusNode: _focusNode,
                            guard: _guard,
                            chromeInsets: layout.covered,
                          ),
                        ),
                        Positioned.fill(child: ImageDropTarget(images: _session.images)),
                        Positioned.fill(
                          child: AudioLayer(
                            audio: _audio,
                            session: _session,
                            chromeInsets: layout.covered,
                            canvasPaper: _notebook.paperColor,
                          ),
                        ),
                        Positioned.fill(child: _buildChrome(layout, tabs)),
                        Positioned.fill(
                          child: EditorSearchLayer(
                            controller: _search,
                            top: layout.covered.top,
                            onClose: _focusNode.requestFocus,
                          ),
                        ),
                        if (_menu case final menu?)
                          Positioned.fill(
                            child: CanvasContextMenu(
                              at: menu.at,
                              actions: menu.actions,
                              onDismiss: _closeMenu,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The top bar swaps its menus when switching between phone and wide
  /// layouts; one disposed while open never reports closing.
  void _resetGuardOnResize(double width) {
    final compact = width < ChromeMetrics.compactWidth;
    if (_compact != null && _compact != compact) _guard.reset();
    _compact = compact;
  }

  /// Keeps document content scrollable clear of the chrome.
  void _applyInsets(EdgeInsets covered) {
    final doc = _session.doc;
    if (doc == null || doc.insets == covered) return;
    // Changing the viewport notifies listeners; never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) doc.setInsets(covered);
    });
  }

  Widget _buildChrome(ChromeLayout layout, OpenNotebooks? tabs) {
    final doc = _session.doc;
    final prefs = _services.preferences;
    final toolbar = EditorToolbar(tools: _session.tools, onStylusOnlyChanged: _setStylusOnly);
    return ListenableBuilder(
      listenable: Listenable.merge([?doc, ?_session.canvasNav, _session.tools]),
      builder: (context, _) => EditorChrome(
        layout: layout,
        hud: _hud,
        onExitFocus: _toggleFocus,
        floatAt: prefs.toolbarFloat,
        onFloatMoved: (at) => prefs.toolbarFloat = at,
        onToolbarHeight: (height) {
          if (mounted) _toolbarHeight.value = height;
        },
        toolbar: toolbar,
        topBar: EditorTopBar(
          title: _notebook.title,
          actions: editorMenuActions(
            context,
            _session,
            onBack: _back,
            onRename: _rename,
            onFocusMode: _toggleFocus,
            onStylusOnly: _setStylusOnly,
            onSettings: _openSettings,
            onFlow: _setFlow,
            onBackground: _pickBackground,
          ),
          undo: _session.undo,
          tabs: tabs,
          audio: AudioBarButton(audio: _audio),
          compactMenuItems: audioMenuItems(context, _audio),
          insert: InsertImageButton(images: _session.images),
          search: BarButton(
            tooltip: 'Search (Ctrl+F)',
            icon: Icons.search_rounded,
            onPressed: _search.open,
          ),
        ),
        navigator: editorPageNavigator(context, _session, width: layout.width),
      ),
    );
  }
}
