import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../domain/surface_element.dart';
import '../../../ink/render/laser_painter.dart';
import '../../../ink/selection/selection_painter.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/tools/content_tools.dart';
import '../../../ink/viewport.dart';
import '../../../ui/floating_panel.dart';
import 'selection_menu.dart';
import 'text_box_editor.dart';

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
    this.page,
  });

  final ContentTools content;
  final ViewportController viewport;
  final ToolSettings tools;

  /// The page rectangle (world) for paged notebooks.
  final Rect? page;

  @override
  State<ContentLayer> createState() => _ContentLayerState();
}

class _ContentLayerState extends State<ContentLayer> with SingleTickerProviderStateMixin {
  late final Ticker _laserTicker = createTicker((_) => _tickLaser());

  /// Where a long press asked to paste (screen, world).
  ({Offset screen, Offset world})? _pasteAt;

  ContentTools get _content => widget.content;

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
    _detach(_content);
    _laserTicker.dispose();
    super.dispose();
  }

  void _attach(ContentTools content) {
    content.laser.addListener(_onLaser);
    content.lassoPath.addListener(_hidePaste);
    content.selection.addListener(_hidePaste);
    content.lasso.onLongPress = (screen, world) {
      if (content.selection.clipboard.isEmpty) return;
      setState(() => _pasteAt = (screen: screen, world: world));
    };
  }

  void _detach(ContentTools content) {
    content.laser.removeListener(_onLaser);
    content.lassoPath.removeListener(_hidePaste);
    content.selection.removeListener(_hidePaste);
    content.lasso.onLongPress = null;
  }

  void _onLaser() {
    if (!_content.laser.isEmpty && !_laserTicker.isActive) _laserTicker.start();
  }

  void _tickLaser() {
    // Frame time (monotonic; fake time in tests).
    final now = SchedulerBinding.instance.currentFrameTimeStamp.inMilliseconds;
    _content.laser.tick(now);
    if (_content.laser.isEmpty) _laserTicker.stop();
  }

  void _hidePaste() {
    if (_pasteAt != null && mounted) setState(() => _pasteAt = null);
  }

  void _editText(SurfaceElement element) {
    _content.selection.clear();
    widget.tools.tool = EditorTool.text;
    _content.text.edit(element);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                accent: scheme.primary,
                handleFill: scheme.surface,
                clip: widget.page,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: LaserPainter(trail: _content.laser, viewport: widget.viewport),
            ),
          ),
        ),
        SelectionMenu(
          selection: _content.selection,
          viewport: widget.viewport,
          tools: widget.tools,
          onEditText: _editText,
          onPaste: _content.pasteAtCentre,
        ),
        TextBoxEditor(session: _content.text, viewport: widget.viewport, tools: widget.tools),
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
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
            ),
          ),
      ],
    );
  }
}
