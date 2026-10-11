import 'package:flutter/material.dart';

/// A [SegmentedButton] label that never wraps mid-word: at large text
/// sizes or on narrow screens it shrinks to fit its segment instead.
class SegmentLabel extends StatelessWidget {
  const SegmentLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
}
