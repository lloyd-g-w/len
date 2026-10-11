import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';

/// Quick eraser controls shown in place of the colours and widths while erasing:
/// whole-stroke / partial toggle and three sizes.
class EraserStrip extends StatelessWidget {
  const EraserStrip({super.key, required this.tools});

  final ToolSettings tools;

  /// Width of the strip in logical pixels.
  static const double width = 4 * 40.0;

  @override
  Widget build(BuildContext context) {
    final eraser = tools.eraser;
    final scheme = Theme.of(context).colorScheme;
    final pixel = eraser.mode == EraserMode.pixel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          tooltip: pixel
              ? 'Partial eraser (tap for whole strokes)'
              : 'Whole-stroke eraser (tap for partial)',
          onPressed: () =>
              tools.eraser = eraser.copyWith(mode: pixel ? EraserMode.stroke : EraserMode.pixel),
          icon: Icon(pixel ? Icons.blur_on_rounded : Icons.gesture_rounded),
        ),
        // Sizes in a recessed track with a tonal selection, like widths.
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final size in EraserConfig.quickSizes)
                Tooltip(
                  message: 'Eraser size ${(size * 2).round()} px',
                  child: Semantics(
                    button: true,
                    selected: eraser.radius == size,
                    child: InkResponse(
                      radius: 20,
                      onTap: () => tools.eraser = eraser.copyWith(radius: size),
                      child: SizedBox.square(
                        dimension: 40,
                        child: Center(
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: eraser.radius == size ? scheme.secondaryContainer : null,
                            ),
                            child: Container(
                              width: 6 + size * 0.6,
                              height: 6 + size * 0.6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: eraser.radius == size
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
