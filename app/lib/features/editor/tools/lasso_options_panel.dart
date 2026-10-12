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
        Text(
          'Draw around ink, text and images to select them. Drag the selection to move it; '
          'its menu restyles, copies, converts to text or links it.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Gaps.sm),
        Text('PDF text: long press it to select.', style: text.bodySmall),
      ],
    );
  }
}
