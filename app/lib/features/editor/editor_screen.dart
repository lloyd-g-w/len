import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/playback_keys.dart';
import '../documents/template_picker.dart';
import '../search/editor/editor_search_controller.dart';
import '../search/editor/editor_search_layer.dart';
import '../settings/settings_screen.dart';
import 'chrome/canvas_guard.dart';
import 'chrome/chrome_metrics.dart';
import 'chrome/editor_chrome.dart';
import 'chrome/editor_tips.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/focus_handle.dart';
import 'chrome/gesture_hud.dart';
import 'chrome/toolbar_slot.dart';
import 'document/document_layout.dart';
import 'editor_chrome_host.dart';
import 'editor_gestures.dart';
import 'editor_import_target.dart';
import 'editor_layers.dart';
import 'editor_lifecycle.dart';
import 'editor_session.dart';
import 'editor_shortcuts.dart';
import 'editor_toolbar.dart';
import 'links/link_actions.dart';
import 'pdf/pdf_layer.dart';
import 'present/presentation.dart';
import 'shared/shared_notebooks.dart';
import 'split/split_controller.dart';
import 'split/split_view.dart';
import 'split/split_view_button.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar/toolbar_config.dart';

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

  /// The notebook and what this editor shares with its other editors.
  late final SharedNotebook _shared = _services.sharedNotebooks.acquire(widget.notebook)
    ..addListener(_onShared);
  Notebook get _notebook => _shared.notebook;
  late final EditorSession _session = EditorSession(
    services: _services,
    shared: _shared,
    onStylusDetected: _onStylusDetected,
    initialView: widget.secondPane
        ? _services.openNotebooks.splitView
        : _services.openNotebooks.viewOf(widget.notebook.id) ??
              EditorViewState.decode(_services.settings.editorView(widget.notebook.id)),
  );

  /// App lifecycle, remote changes, remembering the view, closing.
  late final EditorLifecycle _lifecycle = EditorLifecycle(
    services: _services,
    session: _session,
    secondPane: widget.secondPane,
    inWorkspace: widget.split != null,
  );

  /// This editor as the split view sees it.
  late final SplitPane? _pane = widget.split == null
      ? null
      : SplitPane(
          session: _session,
          secondary: widget.secondPane,
          area: () => _areaKey.currentContext?.findRenderObject() as RenderBox?,
          showMessage: (message) {
            if (mounted) showMessage(context, message);
          },
        );
  final GlobalKey _areaKey = GlobalKey(debugLabel: 'editor area');

  /// Presentation mode (no chrome, laser pointer, page navigation).
  late final Presentation _presentation = Presentation(_session)..addListener(_onPresentation);

  /// Pointer activity that shows the presentation controls.
  final ValueNotifier<int> _presentActivity = ValueNotifier(0);
  final HudController _hud = HudController();

  /// Audio recording and ink replay (features/audio), shared by the
  /// notebook's editors.
  NotebookAudio get _audio => _shared.audio;

  /// One-time tips (stylus side button, multi-finger taps).
  late final TipsController _tips = TipsController(
    seen: (id) => _services.settings.seenTips.contains(id),
    markSeen: _services.settings.markTipSeen,
  );

  /// Whether the last pointer down in the editor was a finger or a pen.
  bool _touchInput = false;

  /// In-notebook search, Ctrl+F (features/search).
  late final EditorSearchController _search;
  final CanvasGuard _guard = CanvasGuard();
  bool? _compact;

  /// Measured height of the toolbar panel (it wraps on narrow screens).
  final ValueNotifier<double?> _toolbarHeight = ValueNotifier(null);

  /// The toolbar's width on one row, kept current as the tools change.
  late final ValueNotifier<double> _toolbarWidth = ValueNotifier(_oneRowWidth());

  double _oneRowWidth() => EditorToolbar.oneRowWidth(
    _session.tools,
    labels: _services.preferences.toolbarLabels,
    config: _services.preferences.toolbarConfig,
  );

  void _onTools() => _toolbarWidth.value = _oneRowWidth();

  /// Focus mode: all chrome hidden.
  bool _focus = false;

  /// The toolbar is in edit mode ("Customise toolbar…").
  bool _customising = false;

  /// Where the canvas context menu is open, if it is.
  EditorMenu? _menu;

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

  late final EditorScreenCommands _commands = EditorScreenCommands(
    back: _back,
    rename: _rename,
    toggleFocus: _toggleFocus,
    setStylusOnly: _setStylusOnly,
    openSettings: _openSettings,
    setFlow: _setFlow,
    pickBackground: _pickBackground,
    openSearch: _search.open,
    customiseToolbar: (on) => setState(() => _customising = on),
    present: _presentation.start,
  );

  @override
  void initState() {
    super.initState();
    _session.gestures
      ..onMultiFingerTap = _onMultiFingerTap
      ..onContextMenu = _openMenu;
    _lifecycle.start();
    // Created now: it takes a result the library asked to show.
    _search = EditorSearchController.forSession(_services, _session, notebookId: _notebook.id);
    _services.openNotebooks.addListener(_onTabs);
    _services.preferences.addListener(_onPreferences);
    _session.undo.addListener(_onEdit);
    _session.tools.addListener(_onTools);
    _audio.onNotice = _onAudioNotice;
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
    _services.routeOwners.forget(this);
    _services.openNotebooks.removeListener(_onTabs);
    _lifecycle.dispose();
    _services.preferences.removeListener(_onPreferences);
    _session.undo.removeListener(_onEdit);
    _session.tools.removeListener(_onTools);
    if (_focus) setImmersive(false);
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
    _toolbarHeight.dispose();
    _toolbarWidth.dispose();
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
    _services.incomingFiles.targets.add(_importTarget);
    _services.routeOwners.current = this; // Dialogs opened by keyboard.
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
    if (openLinkAction(context, _session, at) case final link?) actions.insert(0, link);
    setState(() => _menu = (at: at, actions: actions));
  }

  void _followLink(Paper target) {
    if (mounted && !_closing) _session.commands?.followLink(context, target);
  }

  void _closeMenu() {
    if (_menu != null) setState(() => _menu = null);
  }

  void _onPresentation() {
    if (!mounted) return;
    final active = _presentation.active;
    if (!active && _focus) setImmersive(true); // Back to focus mode.
    if (_pane case final pane?) widget.split!.present(active ? pane : null);
    if (active) _focusNode.requestFocus();
    setState(() {});
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
    _shared.update((n) => n.copyWith(title: title));
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
    _shared.update((n) => n.copyWith(paper: template.style, paperColor: template.color));
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
          bindings: _shortcuts(tabs),
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            // Automatic placement depends on the toolbar's width (its slots);
            // other tool changes don't rebuild the whole editor (the toolbar
            // and chrome listen to the tools themselves).
            child: ListenableBuilder(
              listenable: Listenable.merge([_toolbarWidth, _toolbarHeight]),
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) => _buildArea(context, constraints, tabs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(OpenNotebooks? tabs) => {
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
    if (_presentation.active) ...{
      const SingleActivator(LogicalKeyboardKey.space): () => _presentation.turn(1),
      const SingleActivator(LogicalKeyboardKey.space, shift: true): () => _presentation.turn(-1),
    },
    ...EditorSearchLayer.shortcuts(_search),
    ...?_session.pdf == null ? null : pdfShortcuts(_session.pdf!),
  };

  /// Escape first leaves presentation, then closes a chrome menu opened
  /// with a tap (focus stayed here, out of the menu's reach). The audio
  /// player's keys (Space, ← / →) come before the editor's shortcuts.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final escape = event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;
    if (escape && _presentation.active) {
      _presentation.stop();
      return KeyEventResult.handled;
    }
    return escape && _guard.closeMenus()
        ? KeyEventResult.handled
        : handlePlaybackKey(_audio, event);
  }

  Widget _buildArea(BuildContext context, BoxConstraints constraints, OpenNotebooks? tabs) {
    final media = MediaQuery.of(context);
    final presenting = _presentation.active;
    final layout = ChromeLayout(
      placement: resolvePlacement(
        _services.preferences.toolbarPlacement,
        constraints.maxWidth,
        toolbarWidth: _oneRowWidth(),
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
          // What opens from here (dialogs, sheets) belongs to this editor.
          _services.routeOwners.current = this;
          _touchInput = e.kind != PointerDeviceKind.mouse;
          if (presenting && _touchInput) _presentActivity.value++;
        },
        onPointerHover: (e) {
          // The pointer near the bottom shows the controls.
          if (presenting && e.localPosition.dy > constraints.maxHeight * 0.75) {
            _presentActivity.value++;
          }
        },
        child: EditorLayers(
          key: _areaKey,
          session: _session,
          notebook: _notebook,
          layout: layout,
          focusNode: _focusNode,
          guard: _guard,
          audio: _audio,
          search: _search,
          presentation: _presentation,
          presentActivity: _presentActivity,
          chrome: _buildChrome(layout, tabs),
          onFollowLink: _followLink,
          split: _pane == null ? null : (controller: widget.split!, pane: _pane),
          menu: _menu,
          onCloseMenu: _closeMenu,
        ),
      ),
    );
  }

  Widget _buildChrome(ChromeLayout layout, OpenNotebooks? tabs) => EditorChromeHost(
    session: _session,
    layout: layout,
    commands: _commands,
    title: _notebook.title,
    subtitle: _folderName(),
    audio: _audio,
    hud: _hud,
    tips: _tips,
    customising: _customising,
    onToolbarHeight: (height) {
      if (mounted) _toolbarHeight.value = height;
    },
    tabs: tabs,
    secondPane: widget.secondPane,
    splitButton: (widget.split?.available ?? false) && !widget.secondPane
        ? SplitViewButton(tabs: _services.openNotebooks, notebookId: _notebook.id)
        : null,
    navigatorActivity: _session.doc?.viewport,
  );

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
}
