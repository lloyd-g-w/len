import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/selection/selection_controller.dart';
import '../../../ui/app_theme.dart';
import 'split_controller.dart';

/// Marks [pane] while a selection dragged from the other pane would be
/// dropped (copied) into it, with a preview of the copy where it would
/// land (at this pane's zoom).
class SplitDropHighlight extends StatelessWidget {
  const SplitDropHighlight({super.key, required this.split, required this.pane});

  final SplitController split;
  final SplitPane pane;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: split,
        builder: (context, _) {
          final on = split.dropTarget == pane;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (on) CustomPaint(painter: _ghost()),
              AnimatedSwitcher(
                duration: Motion.fast,
                child: !on
                    ? const SizedBox.expand()
                    : DecoratedBox(
                        // The 2-dp accent outline only; the pane keeps its colours.
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.primary, width: Hairline.rule),
                        ),
                        child: Align(
                          alignment: const Alignment(0, -0.6),
                          // An Ink slab, like the gesture HUD.
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.inverseSurface,
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.fromBorderSide(Surfaces.border(scheme)!),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Gaps.lg,
                                vertical: Gaps.sm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.content_copy_sharp,
                                    size: Glyphs.menu,
                                    color: scheme.onInverseSurface,
                                  ),
                                  const SizedBox(width: Gaps.sm),
                                  Text(
                                    'Drop to copy here',
                                    style: Theme.of(context).textTheme.labelLarge
                                        ?.copyWith(color: scheme.onInverseSurface),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  _GhostPainter? _ghost() {
    final source = split.dragSource?.session.content.selection;
    final picture = source?.picture;
    if (source == null || picture == null || source.isEmpty) return null;
    return _GhostPainter(
      picture: picture,
      centre: SelectionController.boundsOf(source.strokes, source.elements).center,
      at: pane.toLocal(split.dragCentre),
      scale: pane.session.viewport.scale,
    );
  }
}

/// The dragged selection drawn half-transparent at [scale], its world
/// [centre] at [at].
class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.picture,
    required this.centre,
    required this.at,
    required this.scale,
  });

  final ui.Picture picture;
  final Offset centre;
  final Offset at;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..saveLayer(Offset.zero & size, Paint()..color = Tones.light.ink.withValues(alpha: 0.6))
      ..translate(at.dx, at.dy)
      ..scale(scale)
      ..translate(-centre.dx, -centre.dy)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.picture != picture || old.at != at || old.scale != scale || old.centre != centre;
}
