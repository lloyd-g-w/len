import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/elements/text_edit_session.dart';
import '../../../ink/elements/text_layout.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import 'text/list_marker_view.dart';
import 'text/rich_text_controller.dart';
import 'text/rich_text_field.dart';
import 'text/text_box_reveal.dart';
import 'text_format_bar.dart';

/// Edits the session's text box in place: a real text field laid out in
/// world units (exactly as the box will render) and transformed by the
/// viewport, a grip to move it, grips on both sides to change its width,
/// and a formatting bar above it.
class TextBoxEditor extends StatefulWidget {
  const TextBoxEditor({
    super.key,
    required this.session,
    required this.viewport,
    required this.tools,
  });

  final TextEditSession session;
  final ViewportController viewport;
  final ToolSettings tools;

  @override
  State<TextBoxEditor> createState() => _TextBoxEditorState();
}

class _TextBoxEditorState extends State<TextBoxEditor> {
  final RichTextController _text = RichTextController(const TextData());
  final FocusNode _focus = FocusNode(debugLabel: 'TextBoxEditor');
  final GlobalKey _dockedBar = GlobalKey(debugLabel: 'docked format bar');
  final TextBoxReveal _reveal = TextBoxReveal();
  String? _editingId;

  TextEditSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _text
      ..onDataChanged = _push
      ..markerBuilder = (m) => ListMarkerView(
        marker: m,
        onToggle: () {
          _text.toggleChecked(m.line);
          _focus.requestFocus();
        },
      );
    _session.addListener(_onSession);
    _onSession();
  }

  /// The field's text and formatting → the session.
  void _push() => _session.setData(_text.data);

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A new box (or another box) started: load its text and focus it.
  void _onSession() {
    final element = _session.current;
    final id = element?.id;
    if (id == _editingId) {
      // The session may end auto width (box resized or grown to its limit).
      final auto = _session.data.autoWidth;
      if (id != null && _text.box.autoWidth != auto) {
        _text.adoptBox(_text.box.copyWith(autoWidth: auto));
      }
      // List items wrap with hanging indents at the box width.
      if (element != null) _text.wrapWidth = element.rect.width;
      return;
    }
    if (element != null) _text.wrapWidth = element.rect.width;
    _editingId = id;
    if (id == null) return;
    _text.load(_session.data);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null) _focus.requestFocus();
    });
  }

  /// Converts a global pointer position to world coordinates.
  Offset _world(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    return widget.viewport.toWorld(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, widget.viewport]),
      builder: (context, _) {
        final element = _session.current;
        if (element == null) return const SizedBox.shrink();
        final bounds = _screenBounds(element);
        final docked = MediaQuery.sizeOf(context).width < TextFormatBar.dockBelowWidth;
        _reveal.schedule(
          host: context,
          viewport: widget.viewport,
          id: element.id,
          box: bounds,
          bar: docked ? _dockedBar : null,
          top: MediaQuery.paddingOf(context).top + TextBoxReveal.gap,
        );
        final scale = widget.viewport.scale;
        // The box sits on the paper, not the chrome: ink blue in both themes
        // (like the selection handles).
        const accent = AppTheme.seed;
        // The outline sits a few pixels outside the text, which is laid out
        // exactly as it renders.
        final pad = 6 / scale;
        final cursor = 2 / scale;
        final box = SizedBox(
          width: element.rect.width + RichTextField.caretMargin(cursor),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -pad,
                top: -pad,
                right: -pad,
                bottom: -pad,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5 / scale),
                      borderRadius: BorderRadius.circular(4 / scale),
                    ),
                  ),
                ),
              ),
              TextSelectionTheme(
                data: TextSelectionThemeData(
                  selectionColor: accent.withValues(alpha: 0.25),
                  selectionHandleColor: accent,
                ),
                child: DefaultTextEditingShortcuts(
                  child: RichTextField(
                    controller: _text,
                    focusNode: _focus,
                    cursorWidth: cursor,
                    cursorColor: accent,
                    onDone: _session.end,
                  ),
                ),
              ),
            ],
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Transform(
                transform: _matrix(element),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    box,
                    _grip(
                      scale,
                      accent,
                      pad: pad,
                      alignment: Alignment.topLeft,
                      icon: Symbols.open_with_sharp,
                      tooltip: 'Move',
                      onDrag: (d) => _session.setRect(_session.current!.rect.shift(d)),
                    ),
                    for (final side in [Alignment.centerLeft, Alignment.centerRight])
                      _grip(
                        scale,
                        accent,
                        pad: pad,
                        alignment: side,
                        icon: Symbols.drag_indicator_sharp,
                        tooltip: 'Width',
                        onDrag: (d) => _resize(side.x, d),
                      ),
                  ],
                ),
              ),
            ),
            TextFormatBar(
              anchor: bounds,
              dockedKey: _dockedBar,
              controller: _text,
              tools: widget.tools,
              onBoxChanged: (box) => widget.tools.textStyle = box,
              onDelete: () {
                _session.setData(const TextData());
                _session.end();
              },
              onDone: _session.end,
              refocus: _focus.requestFocus,
            ),
          ],
        );
      },
    );
  }

  /// Drags the left (`side` < 0) or right edge of the box by [d] (along
  /// the box's own axis).
  void _resize(double side, Offset d) {
    final e = _session.current;
    if (e == null) return;
    final rot = e.rotation;
    final along = d.dx * math.cos(rot) + d.dy * math.sin(rot);
    final r = e.rect;
    if (side > 0) {
      _session.setWidth(r.left, r.width + along);
    } else {
      final width = math.max(r.width - along, TextLayout.minWidth);
      _session.setWidth(r.right - width, width);
    }
  }

  /// A round handle on the box edge (constant size on screen) that drags
  /// the box in world units.
  Widget _grip(
    double scale,
    Color accent, {
    required double pad,
    required Alignment alignment,
    required IconData icon,
    required String tooltip,
    required ValueChanged<Offset> onDrag,
  }) {
    final size = 22 / scale;
    Offset? last;
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          // Centred on the outline, which is [pad] outside the text.
          offset: Offset(alignment.x * (size / 2 + pad), alignment.y * (size / 2 + pad)),
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => last = _world(d.globalPosition),
              onPanUpdate: (d) {
                final world = _world(d.globalPosition);
                onDrag(world - (last ?? world));
                last = world;
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(icon, size: 14 / scale, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// World box → screen: the viewport transform, then the element's
  /// rotation about its centre.
  Matrix4 _matrix(SurfaceElement e) {
    final v = widget.viewport;
    final centre = v.toScreen(e.rect.center);
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(v.scale, v.scale, 1, 1)
      ..rotateZ(e.rotation)
      ..translateByDouble(-e.rect.width / 2, -e.rect.height / 2, 0, 1);
  }

  Rect _screenBounds(SurfaceElement e) {
    final v = widget.viewport;
    final pts = e.corners.map(v.toScreen).toList();
    final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }
}
