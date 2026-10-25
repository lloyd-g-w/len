import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../toolbar/tool_cluster.dart';
import '../toolbar/toolbar_metrics.dart';
import '../tools/tool_icons.dart';
import 'slot_button.dart';

/// The eraser's quick controls in its sub-bar: three size slots (· • ●,
/// drawn as rings), a hairline, then whole stroke or partial. "Highlighter
/// only" lives in its options; a slot has nothing more to edit.
class EraserStrip extends StatelessWidget {
  const EraserStrip({super.key, required this.tools});

  final ToolSettings tools;

  static const _modes = [
    (EraserMode.stroke, ToolIconKind.eraseStroke, 'Erase whole strokes'),
    (EraserMode.pixel, ToolIconKind.erasePartial, 'Erase partially'),
  ];

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    final chosen = EraserConfig.quickSizes.indexOf(eraser.radius);
    final scheme = Theme.of(context).colorScheme;
    return Flex(
      direction: ToolbarAxis.of(context),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, size) in EraserConfig.quickSizes.indexed)
          SlotButton(
            key: ValueKey('eraser-size-$i'),
            selected: eraser.radius == size,
            tabStop: i == (chosen < 0 ? 0 : chosen),
            tooltip: 'Eraser size ${i + 1}',
            semanticLabel: 'Eraser size ${i + 1}',
            onSelect: () => tools.eraser = eraser.copyWith(radius: size),
            rule: true,
            child: SlotDot(
              diameter: (4 + size * 0.5).clamp(6.0, 20.0),
              selected: eraser.radius == size,
              hollow: true,
            ),
          ),
        const ToolbarDivider(),
        for (final (mode, glyph, label) in _modes)
          SlotButton(
            key: ValueKey('eraser-mode-${mode.name}'),
            selected: eraser.mode == mode,
            tooltip: label,
            semanticLabel: label,
            onSelect: () => tools.eraser = eraser.copyWith(mode: mode),
            rule: true,
            child: IconTheme.merge(
              data: IconThemeData(
                color: eraser.mode == mode ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
              child: ToolIcon(glyph, size: Glyphs.bar),
            ),
          ),
      ],
    );
  }
}
