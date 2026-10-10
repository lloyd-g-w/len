import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ink/input/ink_input_controller.dart';
import '../../ink/input/live_ink.dart';
import '../../ink/navigation/kinetic_pan.dart';
import '../../ink/navigation/viewport_animator.dart';
import '../../ink/surface_model.dart';
import '../../ink/tool_settings.dart';
import '../../ink/tools/content_tools.dart';
import '../../ink/viewport.dart';
import '../../sync/sync_engine.dart';
import '../../ui/measure_size.dart';
import '../../ui/text_prompt.dart';
import '../documents/pdf/pdf_background_cache.dart';
import '../documents/template_picker.dart';
import 'canvas/canvas_menu.dart';
import 'canvas/canvas_navigation.dart';
import 'canvas/canvas_shortcuts.dart';
import 'canvas/canvas_view.dart';
import 'document/document_commands.dart';
import 'document/document_controller.dart';
import 'document/document_layout.dart';
import 'document/document_menu.dart';
import 'document/paged_document_view.dart';
import 'document/undo_target.dart';
import 'editor_pills.dart';
import 'editor_toolbar.dart';
import 'page_navigator.dart';
import 'tools/content_layer.dart';
import 'tools/content_shortcuts.dart';

/// Full-screen editor for a paged notebook or an infinite canvas.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.notebook});

  final Notebook notebook;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final AppServices _services = AppScope.read(context);
  late Notebook _notebook = widget.notebook;
  late final ToolSettings _tools = ToolSettings(
    stylusOnly: _services.settings.stylusOnly,
    store: _services.settings,
  );
  final LiveInk _live = LiveInk();
  late final InkInputController _input;
  late final UndoTarget _undo;
  late final ContentTools _content;
  StreamSubscription<RemoteChanges>? _remoteChanges;

  // Infinite canvas: one surface.
  SurfaceModel? _canvas;
  ViewportController? _canvasViewport;
  CanvasNavigation? _canvasNav;

  // Paged notebook: pages laid out as a document.
  DocumentController? _doc;
  DocumentCommands? _commands;
  PdfBackgroundCache? _backgrounds;
  ViewportAnimator? _docAnimator;

  /// Set once the editor is leaving because its notebook was deleted
  /// remotely, so further sync events don't pop another route.
  bool _closing = false;

  /// Keyboard focus for the editor's shortcuts; reclaimed whenever the
  /// canvas is touched (e.g. after using the width slider).
  final FocusNode _focus = FocusNode(debugLabel: 'EditorScreen');

  bool get _isCanvas => widget.notebook.kind == NotebookKind.canvas;

  @override
  void initState() {
    super.initState();
    if (_isCanvas) {
      final model = _canvas = SurfaceModel(
        surfaceId: _notebook.id,
        repository: _services.strokes,
        elementRepository: _services.elements,
        reader: _services.strokeReader,
      );
      final viewport = _canvasViewport = ViewportController();
      final nav = _canvasNav = _canvasNavigation(viewport);
      _input = _inputFor(model, viewport, kinetic: nav.kinetic);
      _undo = SurfaceUndo(model);
    } else {
      final doc = _doc = _openDocument();
      _commands = DocumentCommands(services: _services, notebook: () => _notebook, doc: doc);
      _backgrounds = PdfBackgroundCache(blobs: _services.blobs, fetch: _services.sync.fetchBlob);
      final animator = _docAnimator = ViewportAnimator(doc.viewport);
      _input = doc.input = _inputFor(
        doc.activeModel,
        doc.pageViewport,
        kinetic: KineticPan(animator, enabled: () => doc.flow == PageFlow.continuous),
      );
      // Paste onto the page in the middle of the screen.
      _content.beforePasteAtCentre = () => doc.activateAt(doc.viewport.size.center(Offset.zero));
      _undo = doc.surfaces;
    }
    _remoteChanges = _services.sync.remoteChanges.listen(_onRemoteChanges);
  }

  DocumentController _openDocument() {
    var pages = _services.pages.pagesOf(_notebook.id);
    if (pages.isEmpty) pages = [_services.pages.addPage(_notebook.id, paper: _notebook.paper)];
    return DocumentController(
      pages: pages,
      strokes: _services.strokes,
      elements: _services.elements,
      flow: PageFlow.parse(_services.settings.pageFlow),
    )..topInset = 64; // Below the title / undo pills.
  }

  /// The input controller (and the lasso, shape, text and laser tools it
  /// routes to) for [model] seen through [viewport]. For documents these
  /// are the active page's model and its page viewport, so tools work in
  /// page coordinates and follow the active page.
  InkInputController _inputFor(
    SurfaceModel model,
    ViewportController viewport, {
    KineticPan? kinetic,
  }) {
    _content = ContentTools(
      model: model,
      viewport: viewport,
      tools: _tools,
      live: _live,
      clipboard: _services.clipboard,
    );
    return InkInputController(
      model: model,
      viewport: viewport,
      tools: _tools,
      live: _live,
      onStylusDetected: _onStylusDetected,
      content: _content,
      kinetic: kinetic,
    );
  }

  CanvasNavigation _canvasNavigation(ViewportController viewport) => CanvasNavigation(
    viewport: viewport,
    reader: _services.strokeReader,
    surfaceId: _notebook.id,
    showMinimap: _services.settings.canvasMinimap,
    onMinimapChanged: (show) => _services.settings.canvasMinimap = show,
  );

  @override
  void dispose() {
    unawaited(_remoteChanges?.cancel());
    _content.dispose(); // Commits a text box still being edited.
    final edited = _undo.canUndo || _undo.canRedo || (_commands?.changed ?? false);
    if (edited) {
      _services.notebooks.touch(_notebook.id);
      // Deferred: syncing notifies listeners (e.g. the library's sync button),
      // which must not happen while the tree is locked during dispose.
      final sync = _services.sync;
      scheduleMicrotask(() => unawaited(sync.syncNow()));
    }
    _focus.dispose();
    _bottomToolbarHeight.dispose();
    _canvas?.dispose();
    _canvasNav?.dispose();
    _canvasViewport?.dispose();
    _docAnimator?.dispose();
    _doc?.dispose();
    _backgrounds?.dispose();
    _live.dispose();
    _tools.dispose();
    super.dispose();
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
    }
    final doc = _doc;
    if (doc != null && changes.pagesOfNotebooks.contains(_notebook.id)) {
      if (_services.pages.pagesOf(_notebook.id).isNotEmpty) _commands!.reload();
      _backgrounds?.retryMissing(); // New pages may bring new PDFs.
    }
    for (final surfaceId in changes.strokeSurfaces) {
      if (surfaceId == _canvas?.surfaceId) _canvas!.reload();
      doc?.surfaces.reload(surfaceId);
    }
  }

  /// The notebook was deleted on another device: close the editor together
  /// with anything open on top of it (dialogs, menus, sheets).
  void _closeDeleted() {
    _closing = true;
    _input.cancelDraw();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('“${_notebook.title}” was deleted on another device.')),
      );
    if (route == null || !route.isActive) return; // Already leaving.
    navigator
      ..popUntil((r) => r == route)
      ..pop();
  }

  void _onStylusDetected() {
    if (_tools.stylusOnly != null) return;
    _setStylusOnly(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Stylus detected — fingers now pan and zoom.'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _setStylusOnly(false)),
      ),
    );
  }

  void _setStylusOnly(bool value) {
    _tools.stylusOnly = value;
    _services.settings.stylusOnly = value;
  }

  void _setFlow(PageFlow flow) {
    _services.settings.pageFlow = flow.name;
    _doc?.setFlow(flow);
  }

  Future<void> _rename() async {
    final title = await showTextPrompt(
      context,
      title: 'Rename',
      initialValue: _notebook.title,
      confirmLabel: 'Rename',
    );
    if (title == null || title.isEmpty || !mounted || _closing) return;
    // Re-read so a concurrent remote change isn't overwritten wholesale.
    final current = _services.notebooks.get(_notebook.id);
    if (current == null) return;
    setState(() => _notebook = _services.notebooks.update(current.copyWith(title: title)));
  }

  static const _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];

  /// Wraps a single-key shortcut so it doesn't fire while text is edited.
  VoidCallback _unlessTyping(VoidCallback action) => () {
    // The focus node belongs to a Focus widget inside the EditableText.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return;
    }
    action();
  };

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _undo.redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _undo.redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): _undo.redo,
    const SingleActivator(LogicalKeyboardKey.keyP): _unlessTyping(
      () => _tools.tool = EditorTool.pen,
    ),
    const SingleActivator(LogicalKeyboardKey.keyH): _unlessTyping(
      () => _tools.tool = EditorTool.highlighter,
    ),
    const SingleActivator(LogicalKeyboardKey.keyE): _unlessTyping(
      () => _tools.tool = EditorTool.eraser,
    ),
    // 1–6: quick colours of the pen / highlighter; [ and ]: thinner / thicker.
    // (Shift+1 and 0 belong to the canvas shortcuts.)
    for (final (i, key) in _digitKeys.indexed)
      SingleActivator(key): _unlessTyping(() => _tools.selectColor(i)),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): _unlessTyping(
      () => _tools.stepWidth(-1),
    ),
    const SingleActivator(LogicalKeyboardKey.bracketRight): _unlessTyping(
      () => _tools.stepWidth(1),
    ),
    ...contentShortcuts(_content, _tools, _unlessTyping),
    if (_canvasNav case final nav?) ...canvasShortcuts(nav, _unlessTyping),
    if (_doc case final doc?) ...{
      const SingleActivator(LogicalKeyboardKey.pageDown): () => doc.goToPage(doc.currentPage + 1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => doc.goToPage(doc.currentPage - 1),
    },
  };

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  // Touching the canvas takes keyboard focus back for the
                  // shortcuts, without competing for the pointer.
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) {
                    if (!_focus.hasFocus) _focus.requestFocus();
                  },
                  child: _buildSurface(),
                ),
              ),
              Positioned.fill(child: _buildContentLayer()),
              SafeArea(child: _buildChrome(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// From this width the toolbar may sit in the top row (if it fits there on
  /// one row, see [_toolbarOnTop]); below it, at the bottom, where the canvas
  /// overlays keep clear of it.
  static const double _wideLayout = 960;

  /// Room the top row needs besides the toolbar: the outer padding, the
  /// title pill at its narrowest, the undo pill (undo, redo, menu) and gaps.
  static const double _minTitleWidth = 160;
  static const double _undoPillWidth = 3 * 48 + 12;
  static const double _topRowReserve = 24 + _minTitleWidth + _undoPillWidth + 24;

  /// Whether the toolbar sits in the top row: on wide screens, when it fits
  /// there on one row (whichever tool is active).
  bool _toolbarOnTop(double width) =>
      width >= _wideLayout && EditorToolbar.oneRowWidth(_tools) + _topRowReserve <= width;

  /// Height of the toolbar while it sits at the bottom (0 while on top).
  final ValueNotifier<double> _bottomToolbarHeight = ValueNotifier(0);

  Widget _buildSurface() {
    final doc = _doc;
    if (doc != null) {
      return PagedDocumentView(
        controller: doc,
        input: _input,
        live: _live,
        backgrounds: _backgrounds,
        fingersNavigate: () => _tools.stylusOnly ?? false,
      );
    }
    return ValueListenableBuilder(
      valueListenable: _bottomToolbarHeight,
      builder: (context, toolbarHeight, _) => CanvasView(
        model: _canvas!,
        navigation: _canvasNav!,
        input: _input,
        live: _live,
        paper: _notebook.paper,
        paperColor: _notebook.paperColor,
        // Keep clear of a toolbar at the bottom (see _buildChrome).
        bottomInset: toolbarHeight > 0 ? toolbarHeight + 24 : 12,
      ),
    );
  }

  /// Selection, text editor and laser over the surface. For documents it
  /// follows the active page (its viewport and clip).
  Widget _buildContentLayer() {
    final doc = _doc;
    if (doc == null) {
      return ContentLayer(content: _content, viewport: _canvasViewport!, tools: _tools);
    }
    return ListenableBuilder(
      listenable: doc, // Notifies when the active page changes.
      builder: (context, _) => ContentLayer(
        content: _content,
        viewport: doc.pageViewport,
        tools: _tools,
        page: doc.pageViewport.contentBounds,
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    final toolbar = EditorToolbar(tools: _tools, onStylusOnlyChanged: _setStylusOnly);
    final title = TitlePill(
      title: _notebook.title,
      onBack: () => Navigator.of(context).maybePop(),
      onRename: _rename,
    );
    final undo = UndoRedoPill(
      target: _undo,
      trailing: _doc == null ? _canvasMenu() : _documentMenu(),
    );
    return ListenableBuilder(
      listenable: _tools, // The toolbar's width depends on its slots.
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => _layoutChrome(constraints, title, toolbar, undo),
      ),
    );
  }

  Widget _layoutChrome(BoxConstraints constraints, Widget title, Widget toolbar, Widget undo) {
    // Wide screens: one top row, the title giving way to the toolbar.
    // Narrower ones: tools move to the bottom where thumbs reach them.
    final width = constraints.maxWidth;
    final wide = _toolbarOnTop(width);
    final titleWidth = wide
        ? (width - _topRowReserve + _minTitleWidth - EditorToolbar.oneRowWidth(_tools)).clamp(
            _minTitleWidth,
            320.0,
          )
        : 0.0;
    if (wide && _bottomToolbarHeight.value != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bottomToolbarHeight.value = 0;
      });
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: titleWidth),
                  child: title,
                ),
                Expanded(child: Center(child: toolbar)),
              ] else ...[
                // A long title shrinks rather than overflowing on phones.
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                const SizedBox(width: 12),
              ],
              undo,
            ],
          ),
          const Spacer(),
          if (!wide)
            MeasureSize(
              onChange: (size) {
                if (mounted) _bottomToolbarHeight.value = size.height;
              },
              child: toolbar,
            ),
          if (_doc != null) ...[const SizedBox(height: 10), _pageNavigator()],
        ],
      ),
    );
  }

  Widget _canvasMenu() => CanvasMenu(navigation: _canvasNav!, onBackground: _pickBackground);

  /// Changes the canvas's template and paper colour.
  Future<void> _pickBackground() async {
    final choice = await showTemplatePicker(
      context,
      initial: PageTemplate(style: _notebook.paper, color: _notebook.paperColor),
      mode: TemplatePickerMode.canvas,
    );
    if (choice == null || !mounted || _closing) return;
    final current = _services.notebooks.get(_notebook.id);
    if (current == null) return;
    final template = choice.template;
    final updated = current.copyWith(paper: template.style, paperColor: template.color);
    setState(() => _notebook = _services.notebooks.update(updated));
  }

  Widget _documentMenu() {
    final doc = _doc!;
    final commands = _commands!;
    return ListenableBuilder(
      listenable: doc,
      builder: (context, _) => DocumentMenu(
        flow: doc.flow,
        bookmarked: doc.pages[doc.currentPage].bookmarked,
        onCommand: (c) => commands.run(context, c, doc.pages[doc.currentPage]),
        onOverview: () => commands.openOverview(context, backgrounds: _backgrounds),
        onGoTo: () => commands.goToPagePrompt(context),
        onInsertPdf: () => commands.insertPdf(context),
        onFlow: _setFlow,
        onExport: (kind) => commands.export(context, kind),
      ),
    );
  }

  Widget _pageNavigator() {
    final doc = _doc!;
    final commands = _commands!;
    return ListenableBuilder(
      listenable: doc,
      builder: (context, _) => PageNavigator(
        index: doc.currentPage,
        count: doc.pages.length,
        bookmarked: doc.pages[doc.currentPage].bookmarked,
        onSelect: doc.goToPage,
        onAddPage: commands.addPage,
        onOverview: () => commands.openOverview(context, backgrounds: _backgrounds),
        onGoTo: () => commands.goToPagePrompt(context),
        onAddWithTemplate: () => commands.addPageWithTemplate(context),
        onInsertPdf: () => commands.insertPdf(context),
      ),
    );
  }
}
