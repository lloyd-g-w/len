import 'package:flutter/material.dart';

import '../../domain/paper.dart';
import '../../ink/render/paper_painter.dart';
import '../../ink/viewport.dart';
import '../../ui/app_theme.dart';

/// A small selectable sample of a paper style, drawn by the editor's own
/// [PaperPainter] so it always matches the real page.
class PaperSwatch extends StatefulWidget {
  const PaperSwatch({
    super.key,
    required this.paper,
    this.color = PaperColor.white,
    required this.selected,
    required this.onTap,
  });

  final PaperStyle paper;
  final PaperColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<PaperSwatch> createState() => _PaperSwatchState();
}

class _PaperSwatchState extends State<PaperSwatch> {
  static const _size = Size(64, 80);

  // A fixed zoomed-out view onto the top-left of a page.
  final _viewport = ViewportController(minScale: 0.1, maxScale: 1)
    ..setSize(_size)
    ..zoomAt(Offset.zero, 0.5);

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = widget.paper.label;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm + 3),
                  border: Border.all(
                    color: widget.selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm - 1),
                    child: CustomPaint(
                      size: _size,
                      painter: PaperPainter(
                        viewport: _viewport,
                        style: widget.paper,
                        paperColor: widget.color,
                        page: const Rect.fromLTWH(-40, -40, 1000, 1000),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: widget.selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
