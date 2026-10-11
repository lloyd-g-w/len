import 'package:flutter/material.dart';

/// A [SegmentedButton] label that never wraps mid-word.
class SegmentLabel extends StatelessWidget {
  const SegmentLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, softWrap: false);
}

/// Shrinks a control (a [SegmentedButton] of [SegmentLabel]s) as a whole
/// when it is wider than the room it has (large text, narrow screens),
/// so every segment keeps the same text size.
class ShrinkToFit extends StatelessWidget {
  const ShrinkToFit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: child);
}
