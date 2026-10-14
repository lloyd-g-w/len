import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/shapes/shape_fill.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../../../ui/group_header.dart';
import '../pen/ink_paper.dart';

/// The fill of closed shapes (the Shapes popover, the selection's Style):
/// a "Fill" heading, then one row of swatches — none, three light tints of
/// the ink's colour, solid — and, for a solid fill, the shared
/// [ColorChoices] block to pick its colour.
class FillChoices extends StatelessWidget {
  const FillChoices({
    super.key,
    required this.fill,
    required this.ink,
    required this.onChanged,
    this.recent = const [],
  });

  /// The current fill; null when the selected shapes differ.
  final ShapeFill? fill;

  /// The ink colour the tints are made from (and a new solid fill's).
  final int ink;

  /// Called with every pick; `fromBlock` for a colour of the [ColorChoices]
  /// block, whose custom picker reports every drag step.
  final void Function(ShapeFill fill, {required bool fromBlock}) onChanged;

  /// Recent colours for the solid colour block.
  final List<int> recent;

  static const List<String> _tintNames = ['Light tint', 'Medium tint', 'Strong tint'];

  String _label(ShapeFill? fill) {
    if (fill == null) return 'Mixed';
    if (fill.isNone) return 'None';
    if (fill.isTint) return _tintNames[ShapeFill.tints.indexOf(fill.tint)];
    return 'Solid';
  }

  @override
  Widget build(BuildContext context) {
    final sheet = InkPaper.of(context);
    final paper = sheet.paper;
    final current = fill;
    final solid = current?.color;
    final size = Targets.touchFirst ? 32.0 : 28.0;
    final target = Targets.touchFirst ? Targets.touch : 36.0;
    Widget dot(ShapeFill choice, int colour, String tooltip, {Widget? child}) => ColorDot(
      key: ValueKey('fill-$tooltip'),
      color: colour,
      size: size,
      target: target,
      tooltip: tooltip,
      selected: choice == current,
      onTap: () => onChanged(choice, fromBlock: false),
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader('Fill', value: _label(current)),
        Wrap(
          children: [
            dot(
              ShapeFill.none,
              paper.toARGB32(),
              'No fill',
              child: Icon(
                Symbols.block_sharp,
                size: Glyphs.menu,
                // On the paper, which is not themed.
                color: sheet.text,
              ),
            ),
            for (final (i, t) in ShapeFill.tints.indexed)
              dot(
                ShapeFill.tint(t),
                // The tint as it shows on the paper.
                Color.alphaBlend(Color(ShapeFill.tint(t).colorFor(ink)!), paper).toARGB32(),
                _tintNames[i],
              ),
            dot(ShapeFill.solid(solid ?? ink | 0xFF000000), solid ?? ink, 'Solid colour'),
          ],
        ),
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: solid != null
              ? Padding(
                  padding: const EdgeInsets.only(top: Gaps.sm),
                  child: ColorChoices(
                    title: 'Fill colour',
                    color: solid,
                    recent: recent,
                    onChanged: (c) => onChanged(ShapeFill.solid(c), fromBlock: true),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
