import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../sync/sync_engine.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import '../audio/audio_layer.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/audio_bar_button.dart';
import '../audio/ui/playback_keys.dart';
import '../documents/template_picker.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import '../settings/settings_screen.dart';
import 'canvas/canvas_empty_hint.dart';
import 'chrome/bar_button.dart';
import 'chrome/canvas_context_menu.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/chrome_metrics.dart';
import 'chrome/editor_chrome.dart';
import 'chrome/editor_tips.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/focus_handle.dart';
import 'chrome/gesture_hud.dart';
import 'chrome/toolbar_slot.dart';
import 'document/document_layout.dart';
import 'editor_actions.dart';
import 'editor_canvas.dart';
import 'editor_gestures.dart';
import 'editor_import_target.dart';
import 'editor_session.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';
import 'images/image_entry_points.dart';
import 'pdf/pdf_layer.dart';
import 'present/presentation.dart';
import 'present/presentation_controls.dart';
import 'split/split_controller.dart';
import 'split/split_drop_highlight.dart';
import 'split/split_view_button.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar/toolbar_config.dart';
import 'toolbar/toolbar_editor.dart';

/// Full-screen editor for a paged notebook or an infinite canvas: the
/// surface, the content tools' layer and the chrome around them.
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

/// Hosts the editor under a [MessageInsets], so every message shown from
/// the editor (its own state included) clears the bottom chrome.
class _EditorHostState extends State<EditorScreen> {
  final _messageInset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _messageInset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MessageInsets(
    bottom: _messageInset,
    child: _EditorView(
      notebook: widget.notebook,
      messageInset: _messageInset,
      split: widget.split,
      secondPane: widget.secondPane,
    ),
  );
}

class _EditorView extends StatefulWidget {
  const _EditorView({
    required this.notebook,
    required this.messageInset,
    this.split,
    this.secondPane = false,
  });

  final Notebook notebook;
  final SplitController? split;
  final bool secondPane;

  /// Updated with the room the bottom chrome takes.
  final ValueNotifier<double> messageInset;

  @override
  State<_EditorView> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<_EditorView> {
  late final AppServices _services = AppScope.read(context);
  late Notebook _notebook = widget.notebook;
  late final EditorSession _session = EditorSession(
    services: _services,
    notebook: () => _notebook,
    onStylusDetected: _onStylusDetected,
    initialView: widget.secondPane
        ? _services.openNotebooks.splitView
        : _services.openNotebooks.viewOf(widget.notebook.id) ??
              EditorViewState.decode(_services.settings.editorView(widget.notebook.id)),
  );

  /// This editor as the split view sees it.
  late final SplitPane? _pane = widget.split == null
      ? null
      : SplitPane(
          session: _session,
          secondary: widget.secondPane,
          area: () => _areaKey.currentContext?.findRenderObject() as RenderBox?,
        );
  final GlobalKey _areaKey = GlobalKey(debugLabel: 'editor area');

  /// Presentation mode (no chrome, laser pointer, page navigation).
  late final Presentation _presentation = Presentation(_session)..addListener(_onPresentation);

  /// Pointer activity that shows the presentation controls.
  final ValueNotifier<int> _presentActivity = ValueNotifier(0);

  /// Commits a text box being typed and saves where the editor looks when
  /// the app goes to the background (it may be killed there without
  /// [dispose]).
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: () {
      _session.content.text.end();
      _saveView();
    },
  );
  final HudController _hud = HudController();

  /// Audio recording and ink replay (features/audio).
  late final NotebookAudio _audio = NotebookAudio(_services, notebookId: widget.notebook.id);

  /// One-time tips (stylus side button, multi-finger taps).
  late final TipsController _tips = TipsController(
    seen: (id) => _services.settings.seenTips.contains(id),
    markSeen: _services.settings.markTipSeen,
  );

  /// Whether the last pointer down in the editor was a finger or a pen.
  bool _touchInput = false;

  /// Pages scrolling, zooming or turning (shows the phone page indicator).
  late final Listenable? _navigatorActivity = _session.doc?.viewport;

  /// In-notebook search, Ctrl+F (features/search).
  late final EditorSearchController _search;
  final CanvasGuard _guard = CanvasGuard();
  bool? _compact;

  /// Measured height of the toolbar panel (it wraps on narrow screens).
  final ValueNotifier<double?> _toolbarHeight = ValueNotifier(null);
  StreamSubscription<RemoteChanges>? _remoteChanges;

  /// Focus mode: all chrome hidden.
  bool _focus = false;

  /// The toolbar is in edit mode ("Customise toolbar…").
  bool _customising = false;

  /// Where the canvas context menu is open, if it is.
  ({Offset at, List<CanvasAction> actions})? _menu;

  /// Set once the editor is leaving because its notebook was deleted
  /// remotely, so further sync events don't pop another route.
  bool _closing = false;

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
    _session.undo.addListener(_onEdit);
    _lifecycle; // Starts listening.
    _audio.onNotice = (message) {
      if (mounted) showMessage(context, message);
    };
    _services.incomingFiles.targets.add(_importTarget);
    // Of two editors (split view), files go to the one used last.
    _focusNode.addListener(_onFocus);
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
    // still mirrors this editor's edits into the other pane, and the
    // presentation puts back the tool (shared, with linked tools) and page
    // layout before the view is saved.
    if (!_closing) _session.content.text.end(); // Counts as an edit below.
    _presentation
      ..removeListener(_onPresentation)
      ..stop()
      ..dispose();
    if (_pane case final pane?) widget.split!.detach(pane);
    _presentActivity.dispose();
    _focusNode.removeListener(_onFocus);
    _services.incomingFiles.targets.remove(_importTarget);
    unawaited(_remoteChanges?.cancel());
    _services.openNotebooks.removeListener(_onTabs);
    if (widget.secondPane) {
      final tabs = _services.openNotebooks;
      // Not after a swap: the pane now shows another notebook.
      if (tabs.splitId == _notebook.id) tabs.splitView = _session.viewState;
    } else {
      _services.openNotebooks.saveView(_notebook.id, _session.viewState);
    }
    _saveView();
    _lifecycle.dispose();
    _services.preferences.removeListener(_onPreferences);
    _session.undo.removeListener(_onEdit);
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
    _tips.dispose();
    _toolbarHeight.dispose();
    _guard.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Remembers this notebook's page, zoom and pan for the next launch.
  void _saveView() {
    // The second pane keeps its place in memory only (it may show the same
    // notebook as the first).
    if (_closing || widget.secondPane || _services.database.isClosed) return;
    _services.settings.setEditorView(_notebook.id, _session.viewState.encode());
  }

  void _onTabs() {
    if (mounted) setState(() {}); // The tab strip may appear or go.
  }

  void _onFocus() {
    if (_focusNode.hasFocus) _services.incomingFiles.targets.add(_importTarget);
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
      if (updated == null || updated.isTrashed) {
        _closeDeleted(trashed: updated != null);
        return;
      }
      setState(() => _notebook = updated);
      _services.openNotebooks.rename(updated.id, updated.title);
    }
    _session.applyRemoteChanges(changes);
  }

  /// The notebook was deleted (or [trashed]) on another device: close the
  /// editor together with anything open on top of it (dialogs, menus,
  /// sheets). Nothing in progress is written to the deleted notebook.
  void _closeDeleted({bool trashed = false}) {
    _closing = true;
    _session.input.cancelDraw();
    _session.content.text.discard();
    _session.content.selection.clear();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    showMessage(
      context,
      '“${_notebook.title}” was ${trashed ? 'moved to the trash' : 'deleted'} '
      'on another device',
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

  void _offerTip(EditorTip tip) {
    final prefs = _services.preferences;
    _tips.offer(
      tip,
      penButton: prefs.penButtonAction,
      twoFingerUndo: prefs.twoFingerTapUndo,
      threeFingerRedo: prefs.threeFingerTapRedo,
    );
  }

  /// After the first edit by finger or pen: how to undo without reaching
  /// for the top bar.
  void _onEdit() {
    if (_touchInput && _session.undo.canUndo) _offerTip(EditorTip.gestures);
  }

  void _onStylusDetected() {
    _offerTip(EditorTip.penButton);
    if (_session.tools.stylusOnly != null) return;
    _setStylusOnly(true);
    showMessage(
      context,
      'Stylus detected: fingers now pan and zoom',
      action: SnackBarAction(label: 'Undo', onPressed: () => _setStylusOnly(false)),
    );
  }

  void _onMultiFingerTap(int fingers) => runMultiFingerTap(_session, fingers, _hud);

  void _openMenu(Offset at) {
    if (!mounted || _closing) return;
    // A long press on PDF text selects the word there instead.
    if (_session.pdf?.selectWordAt(at) ?? false) return;
    final doc = _session.doc;
    final actions = canvasActions(
      _session,
      at,
      bookmarked: doc?.activePageData.bookmarked ?? false,
      onPageCommand: (c) => _session.commands!.run(context, c, doc!.activePageData),
      onFollowLink: _followLink,
    );
    setState(() => _menu = (at: at, actions: actions));
  }

  void _followLink(Paper target) {
    if (mounted && !_closing) _session.commands?.followLink(context, target);
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

  void _onPresentation() {
    if (!mounted) return;
    final active = _presentation.active;
    if (!active && _focus) setImmersive(true); // Back to focus mode.
    if (_pane case final pane?) widget.split!.present(active ? pane : null);
    if (active) _focusNode.requestFocus();
    setState(() {});
  }

  /// Leaves this pane of the split view.
  void _closePane() => _services.openNotebooks.closeSplit();

  Future<void> _rename() async {
    final title = await showTextPrompt(
      context,
      title: 'Rename notebook',
      label: 'Name',
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
      initial: PageTemplate.of(_notebook.paper, color: _notebook.paperColor),
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

  /// The folder the notebook is filed in, shown under its title.
  String? _folderName() {
    final id = _notebook.folderId;
    return id == null ? null : _services.folders.get(id)?.name;
  }

  void _back() => widget.secondPane ? _closePane() : unawaited(Navigator.of(context).maybePop());

  void _openSettings() => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final open = _services.openNotebooks;
    final tabs = open.contains(_notebook.id) && !widget.secondPane ? open : null;
    final presenting = _presentation.active;
    // Back (e.g. Android's) leaves presentation and focus mode before
    // leaving the editor.
    return PopScope(
      canPop: !_focus && !presenting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        presenting ? _presentation.stop() : _toggleFocus();
      },
      child: Scaffold(
        body: CallbackShortcuts(
          bindings: {
            ...editorShortcuts(
              _session,
              toggleFocus: _toggleFocus,
              nextTab: tabs?.cycle,
              previousTab: tabs == null ? null : () => tabs.cycle(backwards: true),
              closeTab: widget.secondPane
                  ? _closePane
                  : tabs == null
                  ? null
                  : () => tabs.close(_notebook.id),
              paste: () => _session.images.paste(context),
            ),
            const SingleActivator(LogicalKeyboardKey.f5): _presentation.toggle,
            if (presenting) ...{
              const SingleActivator(LogicalKeyboardKey.space): () => _presentation.turn(1),
              const SingleActivator(LogicalKeyboardKey.space, shift: true): () =>
                  _presentation.turn(-1),
            },
            ...EditorSearchLayer.shortcuts(_search),
            ...?_session.pdf == null ? null : pdfShortcuts(_session.pdf!),
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            // Escape first closes a chrome menu opened with a tap (focus
            // stayed here, out of the menu's reach). The audio player's
            // keys (Space, ← / →) come before the editor's shortcuts.
            onKeyEvent: (_, event) {
              final escape = event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
              if (escape && _presentation.active) {
                _presentation.stop();
                return KeyEventResult.handled;
              }
              return escape && _guard.closeMenus()
                  ? KeyEventResult.handled
                  : handlePlaybackKey(_audio, event);
            },
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
                      toolbarWidth: EditorToolbar.oneRowWidth(
                        _session.tools,
                        labels: _services.preferences.toolbarLabels,
                        config: _services.preferences.toolbarConfig,
                      ),
                    ),
                    toolbarHeight: _toolbarHeight.value,
                    barHeight: EditorTopBar.heightFor(constraints.maxWidth, tabs),
                    safe: media.padding,
                    hasNavigator: _session.doc != null,
                    width: constraints.maxWidth,
                    focus: _focus || presenting,
                  );
                  _applyInsets(layout.covered);
                  widget.messageInset.value = layout.covered.bottom;
                  _resetGuardOnResize(constraints.maxWidth);
                  return CanvasGuardScope(
                    guard: _guard,
                    child: Listener(
                      onPointerDown: (e) {
                        _touchInput = e.kind != PointerDeviceKind.mouse;
                        if (presenting && _touchInput) _presentActivity.value++;
                      },
                      onPointerHover: (e) {
                        // The pointer near the bottom shows the controls.
                        if (presenting && e.localPosition.dy > constraints.maxHeight * 0.75) {
                          _presentActivity.value++;
                        }
                      },
                      child: Stack(
                        key: _areaKey,
                        children: [
                          Positioned.fill(
                            child: EditorCanvas(
                              session: _session,
                              paper: _notebook.paper,
                              paperColor: _notebook.paperColor,
                              focusNode: _focusNode,
                              guard: _guard,
                              chromeInsets: layout.covered,
                              onFollowLink: _followLink,
                            ),
                          ),
                          if (_session.pdf case final pdf?)
                            Positioned.fill(child: PdfLayer(interaction: pdf)),
                          if (_session.canvas != null && !presenting)
                            Positioned.fill(
                              child: Padding(
                                padding: layout.covered,
                                child: CanvasEmptyHint(
                                  reader: _services.strokeReader,
                                  surfaceId: _notebook.id,
                                  edits: _session.undo,
                                  darkPaper: _notebook.paperColor.isDark,
                                ),
                              ),
                            ),
                          Positioned.fill(child: ImageDropTarget(images: _session.images)),
                          Positioned.fill(
                            child: AudioLayer(
                              audio: _audio,
                              session: _session,
                              chromeInsets: layout.floatingInsets,
                              canvasPaper: _notebook.paperColor,
                            ),
                          ),
                          if (presenting)
                            Positioned.fill(
                              child: PresentationControls(
                                presentation: _presentation,
                                activity: _presentActivity,
                                doc: _session.doc,
                              ),
                            )
                          else ...[
                            Positioned.fill(child: _buildChrome(layout, tabs)),
                            Positioned.fill(
                              child: EditorSearchLayer(
                                controller: _search,
                                top: layout.covered.top,
                                onClose: _focusNode.requestFocus,
                              ),
                            ),
                          ],
                          if (widget.split case final split?)
                            Positioned.fill(
                              child: SplitDropHighlight(split: split, pane: _pane!),
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

  /// Keeps document content scrollable clear of the chrome, and fits
  /// keep canvas content clear of it.
  void _applyInsets(EdgeInsets covered) {
    final doc = _session.doc;
    final nav = _session.canvasNav;
    final same = doc != null
        ? doc.insets == covered
        : nav != null && !nav.waitingForInsets && nav.insets == covered;
    if (same) return;
    // Changing the viewport notifies listeners; never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      doc?.setInsets(covered);
      nav?.setInsets(covered);
    });
  }

  Widget _buildChrome(ChromeLayout layout, OpenNotebooks? tabs) {
    final doc = _session.doc;
    final prefs = _services.preferences;
    final toolbar = _customising
        ? ToolbarEditor(
            tools: _session.tools,
            config: prefs.toolbarConfig,
            onChanged: (config) => prefs.toolbarConfig = config,
            onDone: () => setState(() => _customising = false),
          )
        : EditorToolbar(
            tools: _session.tools,
            onStylusOnlyChanged: _setStylusOnly,
            showLabels: prefs.toolbarLabels,
            config: prefs.toolbarConfig,
          );
    return ListenableBuilder(
      listenable: Listenable.merge([?doc, ?_session.canvasNav, _session.tools]),
      builder: (context, _) => EditorChrome(
        layout: layout,
        hud: _hud,
        tips: _tips,
        onExitFocus: _toggleFocus,
        floatAt: prefs.toolbarFloat,
        onFloatMoved: (at) => prefs.toolbarFloat = at,
        onToolbarHeight: (height) {
          if (mounted) _toolbarHeight.value = height;
        },
        toolbar: toolbar,
        topBar: EditorTopBar(
          title: _notebook.title,
          subtitle: _folderName(),
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
            onSearch: _search.open,
            onCustomiseToolbar: () => setState(() => _customising = true),
            onPresent: _presentation.start,
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
          secondPane: widget.secondPane,
          split: (widget.split?.available ?? false) && !widget.secondPane
              ? SplitViewButton(tabs: _services.openNotebooks, notebookId: _notebook.id)
              : null,
        ),
        navigator: editorPageNavigator(context, _session, width: layout.width),
        navigatorActivity: _navigatorActivity,
      ),
    );
  }
}
