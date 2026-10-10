import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/notebook_page.dart';
import '../../ink/ink_surface.dart';
import '../../ink/input/ink_input_controller.dart';
import '../../ink/input/live_ink.dart';
import '../../ink/surface_model.dart';
import '../../ink/tool_settings.dart';
import '../../ink/tools/content_tools.dart';
import '../../ink/viewport.dart';
import '../../sync/sync_engine.dart';
import '../../ui/floating_panel.dart';
import '../../ui/text_prompt.dart';
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
  late final ViewportController _viewport = _isCanvas
      ? ViewportController()
      : ViewportController(minScale: 0.25, maxScale: 8);
  late final InkInputController _input;
  late final ContentTools _content = ContentTools(
    model: _model,
    viewport: _viewport,
    tools: _tools,
    live: _live,
    clipboard: _services.clipboard,
  );
  StreamSubscription<RemoteChanges>? _remoteChanges;

  /// Pages of a paged notebook; empty for a canvas.
  List<NotebookPage> _pages = const [];
  int _pageIndex = 0;

  /// One model per visited surface, so undo history survives page turns.
  final Map<String, SurfaceModel> _models = {};

  bool _fitted = false;

  /// Set once the editor is leaving because its notebook was deleted
  /// remotely, so further sync events don't pop another route.
  bool _closing = false;

  /// Keyboard focus for the editor's shortcuts; reclaimed whenever the
  /// canvas is touched (e.g. after using the width slider).
  final FocusNode _focus = FocusNode(debugLabel: 'EditorScreen');

  bool get _isCanvas => widget.notebook.kind == NotebookKind.canvas;
  NotebookPage? get _page => _isCanvas ? null : _pages[_pageIndex];
  String get _surfaceId => _page?.id ?? _notebook.id;
  SurfaceModel get _model => _modelFor(_surfaceId);

  @override
  void initState() {
    super.initState();
    if (!_isCanvas) {
      _pages = _services.pages.pagesOf(_notebook.id);
      if (_pages.isEmpty) _pages = [_services.pages.addPage(_notebook.id, paper: _notebook.paper)];
      _viewport.contentBounds = _page!.bounds;
      _viewport.addListener(_fitOnFirstLayout);
    }
    _input = InkInputController(
      model: _model,
      viewport: _viewport,
      tools: _tools,
      live: _live,
      onStylusDetected: _onStylusDetected,
      content: _content,
    );
    _remoteChanges = _services.sync.remoteChanges.listen(_onRemoteChanges);
  }

  @override
  void dispose() {
    unawaited(_remoteChanges?.cancel());
    _content.dispose(); // Commits a text box still being edited.
    final edited = _models.values.any((m) => m.history.canUndo || m.history.canRedo);
    if (edited) {
      _services.notebooks.touch(_notebook.id);
      // Deferred: syncing notifies listeners (e.g. the library's sync button),
      // which must not happen while the tree is locked during dispose.
      final sync = _services.sync;
      scheduleMicrotask(() => unawaited(sync.syncNow()));
    }
    _focus.dispose();
    for (final m in _models.values) {
      m.dispose();
    }
    _viewport.dispose();
    _live.dispose();
    _tools.dispose();
    super.dispose();
  }

  SurfaceModel _modelFor(String surfaceId) => _models.putIfAbsent(
    surfaceId,
    () => SurfaceModel(
      surfaceId: surfaceId,
      repository: _services.strokes,
      elementRepository: _services.elements,
    ),
  );

  void _fitOnFirstLayout() {
    if (_fitted || _viewport.size.isEmpty) return;
    _fitted = true;
    _viewport.fitWidth();
  }

  // ---------------------------------------------------------------------------
  // Pages

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length || index == _pageIndex) return;
    _input.cancelDraw();
    setState(() => _pageIndex = index);
    _input.model = _model;
    // Re-frame once InkSurface has switched to the new page's model, so the
    // viewport change loads the right surface.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewport
        ..contentBounds = _page!.bounds
        ..fitWidth();
    });
  }

  void _addPage() {
    final page = _services.pages.addPage(_notebook.id, paper: _notebook.paper, after: _page);
    setState(() => _pages = _services.pages.pagesOf(_notebook.id));
    _goToPage(_pages.indexWhere((p) => p.id == page.id));
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
    if (!_isCanvas && changes.pagesOfNotebooks.contains(_notebook.id)) {
      final currentId = _page!.id;
      final pages = _services.pages.pagesOf(_notebook.id);
      if (pages.isNotEmpty) {
        final index = pages.indexWhere((p) => p.id == currentId);
        if (index == -1) _input.cancelDraw(); // Current page went away.
        setState(() {
          _pages = pages;
          _pageIndex = index == -1 ? 0 : index;
        });
        _input.model = _model;
        _viewport.contentBounds = _page!.bounds;
      }
    }
    for (final surfaceId in changes.strokeSurfaces) {
      _models[surfaceId]?.reload();
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
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _model.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _model.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _model.redo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _model.redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): _model.redo,
    const SingleActivator(LogicalKeyboardKey.keyP): _unlessTyping(
      () => _tools.tool = EditorTool.pen,
    ),
    const SingleActivator(LogicalKeyboardKey.keyH): _unlessTyping(
      () => _tools.tool = EditorTool.highlighter,
    ),
    const SingleActivator(LogicalKeyboardKey.keyE): _unlessTyping(
      () => _tools.tool = EditorTool.eraser,
    ),
    ...contentShortcuts(_content, _tools, _unlessTyping),
    if (!_isCanvas) ...{
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _goToPage(_pageIndex + 1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _goToPage(_pageIndex - 1),
    },
  };

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final page = _page;
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
                  child: InkSurface(
                    model: _model,
                    viewport: _viewport,
                    input: _input,
                    live: _live,
                    paper: page?.paper ?? _notebook.paper,
                    page: page?.bounds,
                  ),
                ),
              ),
              Positioned.fill(
                child: ContentLayer(
                  content: _content,
                  viewport: _viewport,
                  tools: _tools,
                  page: page?.bounds,
                ),
              ),
              SafeArea(child: _buildChrome(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    final toolbar = EditorToolbar(tools: _tools, onStylusOnlyChanged: _setStylusOnly);
    final title = _TitlePill(
      title: _notebook.title,
      onBack: () => Navigator.of(context).maybePop(),
      onRename: _rename,
    );
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
                  _UndoRedoPill(model: _model),
                ],
              ),
              const Spacer(),
              if (!wide) toolbar,
              if (!_isCanvas) ...[
                const SizedBox(height: 10),
                PageNavigator(
                  index: _pageIndex,
                  count: _pages.length,
                  onSelect: _goToPage,
                  onAddPage: _addPage,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.title, required this.onBack, required this.onRename});

  final String title;
  final VoidCallback onBack;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Tooltip(
                message: 'Rename',
                child: TextButton(
                  onPressed: onRename,
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UndoRedoPill extends StatelessWidget {
  const _UndoRedoPill({required this.model});

  final SurfaceModel model;

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: model.history.canUndo ? model.undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo (Ctrl+Shift+Z)',
              onPressed: model.history.canRedo ? model.redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
