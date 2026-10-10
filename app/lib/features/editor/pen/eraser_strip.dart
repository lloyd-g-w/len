import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';

/// Quick eraser controls shown in place of the presets while erasing:
/// whole-stroke / partial toggle and three sizes.
class EraserStrip extends StatelessWidget {
  const EraserStrip({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    final scheme = Theme.of(context).colorScheme;
    final pixel = eraser.mode == EraserMode.pixel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: pixel
              ? 'Partial eraser (tap for whole strokes)'
              : 'Whole-stroke eraser (tap for partial)',
          onPressed: () =>
              tools.eraser = eraser.copyWith(mode: pixel ? EraserMode.stroke : EraserMode.pixel),
          icon: Icon(pixel ? Icons.blur_on_rounded : Icons.gesture_rounded),
        ),
        for (final size in EraserConfig.quickSizes)
          Tooltip(
            message: 'Eraser size ${(size * 2).round()} px',
            child: InkResponse(
              radius: 18,
              onTap: () => tools.eraser = eraser.copyWith(radius: size),
              child: SizedBox.square(
                dimension: 34,
                child: Center(
                  child: Container(
                    width: 6 + size * 0.6,
                    height: 6 + size * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: eraser.radius == size
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
