import 'dart:async';
import 'dart:ui';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_edit_session.dart';
import '../elements/text_flow_chains.dart';
import '../input/live_ink.dart';
import '../selection/ink_clipboard.dart';
import '../selection/lasso_path.dart';
import '../selection/selection_chrome.dart';
import '../selection/selection_controller.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../viewport.dart';
import 'laser.dart';
import 'laser_tool.dart';
import 'lasso_tool.dart';
import 'pasted_text.dart';
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
    lasso.onEditText = editText;
    _lastTool = tools.tool;
    tools.addListener(_onToolChanged);
    text.addListener(_onTextChanged);
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
    nowMs: clock.nowMs,
  );
  late final ShapeTool shape = ShapeTool(
    model: () => model,
    live: live,
    tools: tools,
    viewport: viewport,
    selection: selection,
    clock: clock,
  );
  late final TextTool textTool = TextTool(session: text, tools: tools, viewport: viewport);
  late final LaserTool laserTool = LaserTool(laser, config: () => tools.laser);

  late EditorTool _lastTool;

  /// The tool to go back to when a text edit started from another tool
  /// ([editText]) ends; null once the user picks a tool themselves.
  EditorTool? _returnTo;

  /// Edits the text box [element] with the text tool (lasso menu, double
  /// tap). When that edit ends, the tool used before comes back, so the
  /// next stroke inks or lassoes instead of doing nothing.
  void editText(SurfaceElement element) {
    selection.clear();
    final previous = tools.tool;
    tools.tool = EditorTool.text;
    if (previous != EditorTool.text) _returnTo = previous;
    text.edit(element);
  }

  /// Starts a text box at [world] with the text tool (the canvas menu's
  /// Add text here). As with [editText], the tool used before comes back
  /// when the box is done, so the next stroke inks again.
  void addTextAt(Offset world) {
    final previous = tools.tool;
    tools.tool = EditorTool.text;
    if (previous != EditorTool.text) _returnTo = previous;
    textTool.startBox(world);
  }

  /// Starts a text box holding [character], typed with the Text tool and
  /// no box open (see [TextTool.startTyping]); false when that doesn't
  /// apply (another tool, a box open, whitespace).
  bool typeText(String character) {
    if (tools.tool != EditorTool.text || text.isEditing || character.trim().isEmpty) return false;
    // Not under the box finished last: on the page in the middle.
    if (textTool.typingUnderLast() == null) beforePasteAtCentre?.call();
    selection.clear();
    textTool.startTyping(character);
    return true;
  }

  /// The tool chosen before the Text tool.
  EditorTool _beforeText = EditorTool.pen;

  /// Esc with the Text tool and no box open: back to the tool before it
  /// (letters type into new boxes meanwhile, see [typeText]); false when
  /// that doesn't apply.
  bool leaveTextTool() {
    if (tools.tool != EditorTool.text || text.isEditing) return false;
    tools.tool = _beforeText;
    return true;
  }

  void _onTextChanged() {
    if (text.isEditing) return;
    final back = _returnTo;
    _returnTo = null;
    if (back != null && tools.tool == EditorTool.text) tools.tool = back;
  }

  /// Text boxes flowing across the pages of a notebook; null on a canvas.
  TextFlowChains? get flows => text.flows;
  set flows(TextFlowChains? value) {
    text.flows = value;
    selection.flows = value;
  }

  SurfaceModel get model => selection.model;

  /// Switches surface (page turn): the selection is dropped and a text
  /// edit (or a curve) in progress is committed to the surface it belongs to. The laser
  /// goes too, unless [laserShift] moves it into the new surface's
  /// coordinates (both pages in view: it keeps showing where it was).
  void switchTo(SurfaceModel value, {Offset? laserShift}) {
    shape.finishCurve(); // On the surface it was drawn on.
    text.model = value;
    selection.model = value;
    lassoPath.clear();
    if (laserShift != null) {
      laser.shift(laserShift);
    } else {
      laser.clear();
    }
  }

  set model(SurfaceModel value) => switchTo(value);

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
  /// made that way (or by an insert or a paste under another tool) stays
  /// live: pressing on it moves or resizes it with the
  /// lasso, pressing elsewhere drops it and uses [tool] again.
  PointerTool? toolAt(EditorTool tool, Offset screen, {bool lasso = false}) {
    final picked = _toolAt(tool, screen, lasso: lasso);
    // Redo brings back an undone curve only until something else is done.
    if (!identical(picked, shape)) shape.curve.forget();
    return picked;
  }

  PointerTool? _toolAt(EditorTool tool, Offset screen, {required bool lasso}) {
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
    final shape = selection.shape;
    return SelectionChrome.hit(frame, viewport, screen, shape: shape) != null ||
        (shape != null &&
            SelectionChrome.shapeHandleAt(shape, viewport, screen, frame: frame) != null) ||
        SelectionChrome.grabs(frame, viewport, screen, shape: shape);
  }

  /// Called before [pasteAtCentre] pastes, e.g. to make the page in the
  /// middle of the screen the one edited.
  VoidCallback? beforePasteAtCentre;

  /// Pastes the clipboard at the centre of the screen, selected; the tool
  /// stays (pressing elsewhere drops the selection, see [toolAt]).
  void pasteAtCentre() {
    if (selection.clipboard.isEmpty) return;
    beforePasteAtCentre?.call();
    selection.paste(viewport.visibleWorld.center);
  }

  /// Adds a text box showing [data] (e.g. pasted text) centred on [at]
  /// (world; the centre of the screen by default) as one undoable edit,
  /// and selects it (the tool stays). It is as wide as its text, but wraps
  /// at [pasteWidthFraction] of the screen.
  void pasteText(TextData data, {Offset? at}) {
    if (data.text.trim().isEmpty) return;
    if (at == null) beforePasteAtCentre?.call();
    final area = viewport.visibleWorld;
    final head = PastedText.add(
      data,
      model: model,
      flows: flows,
      at: at ?? area.center,
      maxWidth: area.width * pasteWidthFraction,
      clock: clock,
    );
    selection.select(const [], [head]);
  }

  /// Widest a pasted text box is, as a fraction of the visible width.
  static const double pasteWidthFraction = 0.6;

  /// Leaving a tool ends what it was doing.
  void _onToolChanged() {
    final tool = tools.tool;
    if (tool == _lastTool) return;
    if (_lastTool == EditorTool.shape) shape.finishCurve();
    // The lasso's selection goes with it; a live one (under another tool)
    // goes with any tool but the lasso, which takes it over.
    if (_lastTool == EditorTool.lasso || tool != EditorTool.lasso) selection.clear();
    if (_lastTool == EditorTool.text) {
      _returnTo = null; // The user picked a tool: keep it.
      text.end();
    }
    if (_lastTool == EditorTool.laser) laser.hover(null); // A mouse's dot goes.
    if (tool == EditorTool.text) _beforeText = _lastTool;
    _lastTool = tool;
  }

  void dispose() {
    tools.removeListener(_onToolChanged);
    viewport.removeListener(_onViewport);
    text.removeListener(_onTextChanged);
    text.end();
    shape.curve.dispose();
    selection.dispose();
    text.dispose();
    lassoPath.dispose();
    laser.dispose();
  }
}
