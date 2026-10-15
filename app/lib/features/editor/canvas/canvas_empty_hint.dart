import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/stroke_reader.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';

/// A quiet "Draw anywhere" note in the middle of an empty infinite canvas
/// (an endless blank page gives no hint how to move around). It fades away
/// for good at the first edit ([edits] notifies).
class CanvasEmptyHint extends StatefulWidget {
  const CanvasEmptyHint({
    super.key,
    required this.reader,
    required this.surfaceId,
    required this.edits,
    this.tools,
    this.darkPaper = false,
  });

  final StrokeReader reader;
  final String surfaceId;
  final Listenable edits;

  /// The editor's tools: with "Draw with finger" off one finger moves the
  /// canvas, and the touch wording says so. Null: fingers draw.
  final ToolSettings? tools;

  /// The hint sits on the paper, so its colour follows the paper, not the
  /// UI theme (readable at about 5:1 either way).
  final bool darkPaper;

  @override
  State<CanvasEmptyHint> createState() => _CanvasEmptyHintState();
}

class _CanvasEmptyHintState extends State<CanvasEmptyHint> {
  bool _empty = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    widget.edits.addListener(_onEdit);
    unawaited(_check());
  }

  Future<void> _check() async {
    final bounds = await widget.reader.contentBounds(widget.surfaceId);
    if (mounted && bounds == null && !_edited) setState(() => _empty = true);
  }

  void _onEdit() {
    _edited = true;
    if (_empty) setState(() => _empty = false);
  }

  @override
  void dispose() {
    widget.edits.removeListener(_onEdit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = widget.darkPaper
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _empty ? 1 : 0,
        duration: Motion.slow,
        curve: Motion.standard,
        child: Center(
          // Scaled down where the room is short (the soft keyboard up on a
          // phone held sideways).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(Gaps.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.gesture_sharp, size: Glyphs.empty, color: colour),
                  const SizedBox(height: Gaps.sm),
                  Text(
                    'Draw anywhere',
                    style: theme.textTheme.titleMedium?.copyWith(color: colour),
                  ),
                  const SizedBox(height: Gaps.xs),
                  ListenableBuilder(
                    listenable: widget.tools ?? widget.edits,
                    builder: (context, _) => Text(
                      // By input, not platform: a tablet with a mouse, or a
                      // touch screen on the web, gets its own words.
                      !Targets.touchFirst
                          ? 'Scroll to move, Ctrl + scroll to zoom\nRight-click for more options'
                          : (widget.tools?.fingersNavigate ?? false)
                          ? 'Drag to move, pinch to zoom\nLong-press for more options'
                          : 'Two fingers move and zoom\nLong-press for more options',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colour),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
