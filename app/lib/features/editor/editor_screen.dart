import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../ink/ink_surface.dart';
import '../../ink/input/ink_input_controller.dart';
import '../../ink/input/live_ink.dart';
import '../../ink/surface_model.dart';
import '../../ink/tool_settings.dart';
import '../../ink/viewport.dart';
import '../../sync/sync_engine.dart';
import '../../ui/text_prompt.dart';
import '../documents/pdf/pdf_background_cache.dart';
import 'document/document_commands.dart';
import 'document/document_controller.dart';
import 'document/document_layout.dart';
import 'document/document_menu.dart';
import 'document/paged_document_view.dart';
import 'document/undo_target.dart';
import 'editor_pills.dart';
import 'editor_toolbar.dart';
import 'page_navigator.dart';

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
  StreamSubscription<RemoteChanges>? _remoteChanges;

  // Infinite canvas: one surface.
  SurfaceModel? _canvas;
  ViewportController? _canvasViewport;

  // Paged notebook: pages laid out as a document.
  DocumentController? _doc;
  DocumentCommands? _commands;
  PdfBackgroundCache? _backgrounds;

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
      final model = _canvas = SurfaceModel(surfaceId: _notebook.id, repository: _services.strokes);
      final viewport = _canvasViewport = ViewportController();
      _input = _inputFor(model, viewport);
      _undo = SurfaceUndo(model);
    } else {
      final doc = _doc = _openDocument();
      _commands = DocumentCommands(services: _services, notebook: () => _notebook, doc: doc);
      _backgrounds = PdfBackgroundCache(blobs: _services.blobs, fetch: _services.sync.fetchBlob);
      _input = doc.input = _inputFor(doc.activeModel, doc.pageViewport);
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
      flow: PageFlow.parse(_services.settings.pageFlow),
    )..topInset = 64; // Below the title / undo pills.
  }

  InkInputController _inputFor(SurfaceModel model, ViewportController viewport) =>
      InkInputController(
        model: model,
        viewport: viewport,
        tools: _tools,
        live: _live,
        onStylusDetected: _onStylusDetected,
      );

  @override
  void dispose() {
    unawaited(_remoteChanges?.cancel());
    final edited = _undo.canUndo || _undo.canRedo || (_commands?.changed ?? false);
    if (edited) {
      _services.notebooks.touch(_notebook.id);
      // Deferred: syncing notifies listeners (e.g. the library's sync button),
      // which must not happen while the tree is locked during dispose.
      final sync = _services.sync;
      scheduleMicrotask(() => unawaited(sync.syncNow()));
    }
    _focus.dispose();
    _canvas?.dispose();
    _canvasViewport?.dispose();
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
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    if (focused is EditableText) return;
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
    for (final (i, key) in _digitKeys.indexed)
      SingleActivator(key): _unlessTyping(() => _tools.selectColor(i)),
    const SingleActivator(LogicalKeyboardKey.bracketLeft): _unlessTyping(
      () => _tools.stepWidth(-1),
    ),
    const SingleActivator(LogicalKeyboardKey.bracketRight): _unlessTyping(
      () => _tools.stepWidth(1),
    ),
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
              SafeArea(child: _buildChrome(context)),
            ],
          ),
        ),
      ),
    );
  }

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
    return InkSurface(
      model: _canvas!,
      viewport: _canvasViewport!,
      input: _input,
      live: _live,
      paper: _notebook.paper,
    );
  }

  Widget _buildChrome(BuildContext context) {
    final toolbar = EditorToolbar(tools: _tools, onStylusOnlyChanged: _setStylusOnly);
    final title = TitlePill(
      title: _notebook.title,
      onBack: () => Navigator.of(context).maybePop(),
      onRename: _rename,
    );
    final undo = UndoRedoPill(target: _undo, trailing: _doc == null ? null : _documentMenu());
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide screens: one top row. Narrow screens: tools move to the bottom
        // where thumbs reach them.
        final wide = constraints.maxWidth >= 860;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wide) ...[
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: title),
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
              if (!wide) toolbar,
              if (_doc != null) ...[const SizedBox(height: 10), _pageNavigator()],
            ],
          ),
        );
      },
    );
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
