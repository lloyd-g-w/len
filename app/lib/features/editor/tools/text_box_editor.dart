import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/surface_element.dart';
import '../../../ink/elements/text_edit_session.dart';
import '../../../ink/elements/text_layout.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import 'text_format_bar.dart';

/// Edits the session's text box in place: a real [TextField] laid out in
/// world units (exactly as the box will render) and transformed by the
/// viewport, a grip to move it, a grip to change its width, and a
/// formatting bar above it.
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
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'TextBoxEditor');
  String? _editingId;

  TextEditSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _onSession();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A new box (or another box) started: load its text and focus it.
  void _onSession() {
    final id = _session.current?.id;
    if (id == _editingId) return;
    _editingId = id;
    if (id == null) return;
    _text.value = TextEditingValue(
      text: _session.data.text,
      selection: TextSelection.collapsed(offset: _session.data.text.length),
    );
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
        final scale = widget.viewport.scale;
        final data = _session.data;
        final accent = Theme.of(context).colorScheme.primary;
        // The outline sits a few pixels outside the text, which is laid out
        // exactly as it renders.
        final pad = 6 / scale;
        final box = SizedBox(
          width: element.rect.width,
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
              DefaultTextEditingShortcuts(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.escape): _session.end},
                  child: TextField(
                    key: const ValueKey('text-box-field'),
                    controller: _text,
                    focusNode: _focus,
                    maxLines: null,
                    style: TextLayout.styleOf(data),
                    textAlign: TextLayout.alignOf(data),
                    cursorColor: accent,
                    cursorWidth: 2 / scale,
                    decoration: const InputDecoration.collapsed(hintText: null),
                    onChanged: (text) => _session.setData(_session.data.copyWith(text: text)),
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
                      icon: Icons.open_with_rounded,
                      tooltip: 'Move',
                      onDrag: (d) => _session.setRect(element.rect.shift(d)),
                    ),
                    _grip(
                      scale,
                      accent,
                      pad: pad,
                      alignment: Alignment.centerRight,
                      icon: Icons.width_normal_outlined,
                      tooltip: 'Width',
                      onDrag: (d) {
                        final r = _session.current!.rect;
                        _session.setRect(Rect.fromLTWH(r.left, r.top, r.width + d.dx, r.height));
                      },
                    ),
                  ],
                ),
              ),
            ),
            TextFormatBar(
              anchor: _screenBounds(element),
              data: data,
              tools: widget.tools,
              onChanged: (d) {
                // The field holds the latest text, even before a rebuild.
                _session.setData(d.copyWith(text: _text.text));
                widget.tools.textStyle = d;
              },
              onDelete: () {
                _session.setData(data.copyWith(text: ''));
                _session.end();
              },
              onDone: _session.end,
            ),
          ],
        );
      },
    );
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
