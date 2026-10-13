import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../pen/option_controls.dart';

/// The lasso's options: it has no settings, so this says what it does.
class LassoOptionsPanel extends StatelessWidget {
  const LassoOptionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OptionHeader('Lasso'),
        const SizedBox(height: Gaps.sm),
        Text('Circle ink, text or images to select them.', style: text.bodyMedium),
        const SizedBox(height: Gaps.xs),
        Text('Drag to move them, or use the menu that appears.', style: text.bodyMedium),
        const SizedBox(height: Gaps.sm),
        Text('To select PDF text, long-press it', style: text.bodySmall),
      ],
    );
  }
}
