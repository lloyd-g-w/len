import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/shapes/shape_fill.dart';
import '../../../ui/color_picker/color_swatches.dart';
import 'fill_choices.dart';

/// The fill of the selected closed shapes ([Stroke.isClosed]) in the
/// selection's Style panel: each change is one undoable edit. A tint is
/// made from each shape's own ink colour.
class SelectionFill extends StatefulWidget {
  const SelectionFill({super.key, required this.selection, required this.recent});

  final SelectionController selection;
  final List<int> recent;

  @override
  State<SelectionFill> createState() => _SelectionFillState();
}

class _SelectionFillState extends State<SelectionFill> {
  /// A custom solid colour not yet applied: the custom picker reports every
  /// drag step, so it is applied once it has rested for [_settle] (or the
  /// panel closes), as the Style colours are.
  ShapeFill? _pending;
  Timer? _settleTimer;
  static const _settle = Duration(milliseconds: 400);

  @override
  void dispose() {
    _settleTimer?.cancel();
    // After the tree is unlocked: an edit notifies listeners.
    if (_pending != null) scheduleMicrotask(_commit);
    super.dispose();
  }

  void _changed(ShapeFill fill, {required bool fromBlock}) {
    _settleTimer?.cancel();
    final colour = fill.color;
    final preset =
        !fromBlock ||
        colour == null ||
        ColorSwatches.palette.contains(colour) ||
        widget.recent.any((r) => r | 0xFF000000 == colour);
    if (preset) {
      _pending = null;
      _apply(fill);
      return;
    }
    setState(() => _pending = fill);
    _settleTimer = Timer(_settle, _commit);
  }

  void _commit() {
    final fill = _pending;
    if (fill == null) return;
    _pending = null;
    _apply(fill);
  }

  void _apply(ShapeFill fill) => widget.selection.refill((s) => fill.colorFor(s.color));

  @override
  Widget build(BuildContext context) {
    final shapes = [
      for (final s in widget.selection.strokes)
        if (s.isClosed) s,
    ];
    final fills = {for (final s in shapes) ShapeFill.of(s.style.fill, s.color)};
    final inks = {for (final s in shapes) s.color | 0xFF000000};
    return FillChoices(
      fill: _pending ?? (fills.length == 1 ? fills.single : null),
      ink: inks.length == 1 ? inks.single : (shapes.firstOrNull?.color ?? 0xFF000000),
      recent: widget.recent,
      onChanged: _changed,
    );
  }
}
