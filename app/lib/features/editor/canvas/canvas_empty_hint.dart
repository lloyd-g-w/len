import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/stroke_reader.dart';
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
  });

  final StrokeReader reader;
  final String surfaceId;
  final Listenable edits;

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

  static bool get _touchFirst => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _empty ? 1 : 0,
        duration: Motion.slow,
        curve: Motion.standard,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gesture_rounded, size: 40, color: colour),
                const SizedBox(height: Gaps.sm),
                Text('Draw anywhere', style: theme.textTheme.titleMedium?.copyWith(color: colour)),
                const SizedBox(height: Gaps.xs),
                Text(
                  _touchFirst
                      ? 'Drag with two fingers to move, pinch to zoom.\n'
                            'Long-press for more.'
                      : 'Scroll to move, Ctrl + scroll to zoom.\nRight-click for more.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colour),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
