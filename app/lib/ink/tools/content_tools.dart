import 'dart:async';
import 'dart:ui';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_edit_session.dart';
import '../elements/text_layout.dart';
import '../input/live_ink.dart';
import '../selection/ink_clipboard.dart';
import '../selection/lasso_path.dart';
import '../selection/selection_chrome.dart';
import '../selection/selection_controller.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../undo_history.dart';
import '../viewport.dart';
import 'laser.dart';
import 'lasso_tool.dart';
import 'pointer_tool.dart';
import 'shape_tool.dart';
import 'text_tool.dart';

/// The editing tools beyond pens and the eraser — lasso, shapes, text and
/// the laser pointer — with the state they share with the UI (selection,
/// lasso path, text session, laser trail), for one editor.
class ContentTools {
  ContentTools({
    required SurfaceModel model,
    required this.viewport,
    required this.tools,
    required this.live,
    required InkClipboard clipboard,
    this.clock = const Clock(),
  }) : selection = SelectionController(model: model, clipboard: clipboard, clock: clock),
       text = TextEditSession(model: model, clock: clock) {
    lasso.onEditText = (element) {
      tools.tool = EditorTool.text;
      text.edit(element);
    };
    tools.addListener(_onToolChanged);
    viewport.addListener(_onViewport);
    _onViewport();
  }

  /// Selection frames keep a constant margin on screen.
  static const double framePadding = 10;

  void _onViewport() => selection
    ..framePadding = framePadding / viewport.scale
    ..pixelScale = viewport.scale * _devicePixelRatio;

  static double get _devicePixelRatio =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;
  final Clock clock;

  final SelectionController selection;
  final TextEditSession text;
  final LassoPath lassoPath = LassoPath();
  final LaserTrail laser = LaserTrail();

  late final LassoTool lasso = LassoTool(
    selection: selection,
    viewport: viewport,
    path: lassoPath,
    config: () => tools.lasso,
  );
  late final ShapeTool shape = ShapeTool(
    model: () => model,
    live: live,
    tools: tools,
    viewport: viewport,
    clock: clock,
  );
  late final TextTool textTool = TextTool(session: text, tools: tools, viewport: viewport);
  late final LaserTool laserTool = LaserTool(laser, config: () => tools.laser);

  EditorTool _lastTool = EditorTool.pen;

  SurfaceModel get model => selection.model;

  /// Switches surface (page turn): the selection is dropped and a text
  /// edit in progress is committed to the surface it belongs to.
  set model(SurfaceModel value) {
    text.model = value;
    selection.model = value;
    lassoPath.clear();
    laser.clear();
  }

  /// The pointer tool for [tool], or null for inking tools (PDF text is
  /// selected with a long press).
  PointerTool? toolFor(EditorTool tool) => switch (tool) {
    EditorTool.lasso => lasso,
    EditorTool.shape => shape,
    EditorTool.text => textTool,
    EditorTool.laser => laserTool,
    EditorTool.pen || EditorTool.highlighter || EditorTool.eraser => null,
  };

  /// The pointer tool for a press at [screen] with [tool] selected. [lasso]
  /// (the stylus side button set to lasso) forces the lasso. A selection
  /// made that way stays live: pressing on it moves or resizes it with the
  /// lasso, pressing elsewhere drops it and uses [tool] again.
  PointerTool? toolAt(EditorTool tool, Offset screen, {bool lasso = false}) {
    if (lasso) return this.lasso;
    if (tool != EditorTool.lasso && !selection.isEmpty) {
      if (holds(screen)) return this.lasso;
      selection.clear();
    }
    return toolFor(tool);
  }

  /// Selects everything in [area] (world) on the current surface with the
  /// lasso tool, e.g. "select all on this page".
  ///
  /// The area is loaded for the moment only (a view of its own, forgotten
  /// once it is in memory): what is selected stays while selected, the
  /// rest may be evicted again. With a background reader the selection
  /// follows once the area is read (unless the surface changed meanwhile).
  void selectAllIn(Rect area) {
    tools.tool = EditorTool.lasso;
    final model = this.model;
    final view = Object();
    model.ensureLoaded(area, view: view);
    void select() {
      model.forgetView(view);
      if (!identical(model, this.model)) return;
      selection.select(model.strokesNear(area), model.elementsNear(area));
    }

    if (!model.isLoading) return select();
    unawaited(model.loaded.then((_) => select()));
  }

  /// Whether a press at [screen] belongs to what the tools are working on
  /// (the selection or its handles), so a multi-page view should keep the
  /// current page active rather than switch to the page under the pointer.
  bool holds(Offset screen) {
    final frame = selection.frame;
    if (frame == null || selection.isEmpty) return false;
    return SelectionChrome.hit(frame, viewport, screen) != null ||
        frame.contains(viewport.toWorld(screen));
  }

  /// Called before [pasteAtCentre] pastes, e.g. to make the page in the
  /// middle of the screen the one edited.
  VoidCallback? beforePasteAtCentre;

  /// Pastes the clipboard at the centre of the screen (lasso tool on).
  void pasteAtCentre() {
    if (selection.clipboard.isEmpty) return;
    tools.tool = EditorTool.lasso;
    beforePasteAtCentre?.call();
    selection.paste(viewport.visibleWorld.center);
  }

  /// Adds a text box showing [data] (e.g. pasted text) at the centre of
  /// the screen as one undoable edit, and selects it with the lasso. It is
  /// as wide as its text, but wraps at [pasteWidthFraction] of the screen.
  void pasteText(TextData data) {
    if (data.text.trim().isEmpty) return;
    tools.tool = EditorTool.lasso;
    beforePasteAtCentre?.call();
    final area = viewport.visibleWorld;
    var text = data.copyWith(autoWidth: true);
    var width = TextLayout.naturalWidth(text);
    final limit = area.width * pasteWidthFraction;
    if (width > limit) {
      width = limit;
      text = text.copyWith(autoWidth: false);
    }
    final height = TextLayout.heightOf(text, width);
    final element = SurfaceElement(
      id: clock.newId(),
      surfaceId: model.surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromCenter(center: area.center, width: width, height: height),
      z: model.topZ + 1,
      createdAt: clock.nowMs(),
      data: text.toJson(),
    );
    model.commit(InkEdit(addedElements: [element]));
    selection.select(const [], [element]);
  }

  /// Widest a pasted text box is, as a fraction of the visible width.
  static const double pasteWidthFraction = 0.6;

  /// Leaving a tool ends what it was doing.
  void _onToolChanged() {
    final tool = tools.tool;
    if (tool == _lastTool) return;
    if (_lastTool == EditorTool.lasso) selection.clear();
    if (_lastTool == EditorTool.text) text.end();
    if (_lastTool == EditorTool.laser) laser.hover(null); // A mouse's dot goes.
    _lastTool = tool;
  }

  void dispose() {
    tools.removeListener(_onToolChanged);
    viewport.removeListener(_onViewport);
    text.end();
    selection.dispose();
    text.dispose();
    lassoPath.dispose();
    laser.dispose();
  }
}
