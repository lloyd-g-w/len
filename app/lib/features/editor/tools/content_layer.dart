import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/images/image_crop_session.dart';
import '../../../ink/selection/selection_painter.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/content_tools.dart';
import '../../../ink/tools/curve_guide_painter.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../images/image_crop_overlay.dart';
import '../recognition/convert_to_text_dialog.dart';
import 'laser_overlay.dart';
import 'selection_menu.dart';
import 'text_box_editor.dart';
import 'text_box_semantics.dart';

/// Everything the lasso, text and laser tools show over the ink: the
/// lasso and selection (with its menu), the text box being edited, the
/// laser trail and the long-press paste menu.
///
/// Lies over the [InkSurface] in the same coordinates; only its menus and
/// the text editor take pointer events — the rest falls through to the
/// surface.
class ContentLayer extends StatefulWidget {
  const ContentLayer({
    super.key,
    required this.content,
    required this.viewport,
    required this.tools,
    this.pages,
    this.selectionActions,
  });

  final ContentTools content;

  /// Commands the editor adds to the selection menu (links).
  final List<SelectionExtraAction> Function()? selectionActions;
  final ViewportController viewport;
  final ToolSettings tools;

  /// The page rectangles (world) for paged notebooks: the selection shows
  /// on pages only.
  final List<Rect>? pages;

  @override
  State<ContentLayer> createState() => _ContentLayerState();
}

class _ContentLayerState extends State<ContentLayer> {
  /// Where a long press asked to paste (screen, world).
  ({Offset screen, Offset world})? _pasteAt;

  /// The image being cropped, if any.
  ImageCropSession? _crop;

  ContentTools get _content => widget.content;

  /// The part of the active surface on screen (world): the visible part of
  /// the page (its frame starts at the page viewport's origin), or of the
  /// canvas.
  Rect _visibleSurface() {
    final visible = widget.viewport.visibleWorld;
    final page = widget.pages?.where((r) => r.contains(const Offset(1, 1))).firstOrNull;
    if (page == null || !page.overlaps(visible)) return visible;
    return visible.intersect(page);
  }

  @override
  void initState() {
    super.initState();
    _attach(_content);
  }

  @override
  void didUpdateWidget(ContentLayer old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _detach(old.content);
      _attach(widget.content);
    }
  }

  @override
  void dispose() {
    _endCrop(commit: true, disposing: true);
    _detach(_content);
    super.dispose();
  }

  void _attach(ContentTools content) {
    content.lassoPath.addListener(_hidePaste);
    content.selection.addListener(_hidePaste);
    content.lasso.onLongPress = (screen, world) {
      if (content.selection.clipboard.isEmpty) return;
      setState(() => _pasteAt = (screen: screen, world: world));
    };
  }

  void _startCrop(SurfaceElement element) {
    _endCrop(commit: true);
    _content.selection.clear();
    setState(() {
      _crop = ImageCropSession(model: _content.model, element: element)
        ..onAbandoned = () => _endCrop(commit: false);
    });
  }

  /// Leaves crop mode, storing the crop when [commit] is set, and selects
  /// the image again (not while [disposing]: the editor is closing).
  void _endCrop({required bool commit, bool disposing = false}) {
    final session = _crop;
    if (session == null) return;
    _crop = null;
    final element = commit ? session.commit() : session.element;
    session.dispose();
    if (disposing || !mounted) return;
    setState(() {});
    if (identical(_content.model, session.model) &&
        _content.model.elementById(element.id) != null) {
      _content.selection.select(const [], [_content.model.elementById(element.id)!]);
    }
  }

  void _detach(ContentTools content) {
    content.lassoPath.removeListener(_hidePaste);
    content.selection.removeListener(_hidePaste);
    content.lasso.onLongPress = null;
  }

  void _hidePaste() {
    if (_pasteAt != null && mounted) setState(() => _pasteAt = null);
  }

  @override
  Widget build(BuildContext context) {
    final recognition = AppScope.of(context).recognition;
    final pasteAt = _pasteAt;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: SelectionPainter(
                selection: _content.selection,
                lasso: _content.lassoPath,
                viewport: widget.viewport,
                accent: AppTheme.seed, // handles sit on the paper, not the chrome
                handleFill: Palette.paper,
                clip: widget.pages,
                // Fingers cover handles: larger on touch-first devices.
                handleScale: Targets.touchFirst ? SelectionPainter.touchScale : 1,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: CurveGuidePainter(
                guide: _content.shape.curve.guide,
                viewport: widget.viewport,
                accent: AppTheme.seed,
                handleFill: Palette.paper,
                handleScale: Targets.touchFirst ? SelectionPainter.touchScale : 1,
              ),
            ),
          ),
        ),
        LaserOverlay(trail: _content.laser, viewport: widget.viewport),
        SelectionMenu(
          selection: _content.selection,
          viewport: widget.viewport,
          tools: widget.tools,
          onEditText: _content.editText,
          onPaste: _content.pasteAtCentre,
          onCrop: _startCrop,
          onConvertToText: () => convertSelectionToText(
            context,
            recognition: recognition,
            selection: _content.selection,
            area: _visibleSurface,
          ),
          convertUnavailable: recognition.isSupported ? null : recognition.unsupportedReason,
          extraActions: widget.selectionActions,
        ),
        TextBoxSemantics(content: _content, viewport: widget.viewport),
        TextBoxEditor(session: _content.text, viewport: widget.viewport, tools: widget.tools),
        if (_crop case final crop?)
          ImageCropOverlay(
            session: crop,
            viewport: widget.viewport,
            onDone: () => _endCrop(commit: true),
            onCancel: () => _endCrop(commit: false),
          ),
        if (pasteAt != null)
          Positioned(
            left: pasteAt.screen.dx - 48,
            top: pasteAt.screen.dy - 64,
            child: FloatingPanel(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _pasteAt = null);
                  _content.selection.paste(pasteAt.world);
                },
                icon: const Icon(Symbols.content_paste_sharp, size: Glyphs.menu),
                label: const Text('Paste'),
              ),
            ),
          ),
      ],
    );
  }
}
