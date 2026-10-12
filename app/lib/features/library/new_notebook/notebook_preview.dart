import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../documents/template_preview.dart';
import '../notebook_cover.dart';

/// A live preview of the notebook being created: its cover next to its
/// first page (or the canvas background), sized to fit [height].
class NotebookPreview extends StatelessWidget {
  const NotebookPreview({
    super.key,
    required this.kind,
    required this.coverColor,
    required this.template,
    required this.height,
  });

  final NotebookKind kind;
  final int coverColor;
  final PageTemplate template;

  /// Height of the cover and page; less if the width does not allow it.
  final double height;

  bool get _canvas => kind == NotebookKind.canvas;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Canvases show a landscape window onto their endless background.
    final pageSize = _canvas ? const Size(4, 3) : template.size;
    final aspect = pageSize.width / pageSize.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cover (0.72) + gap (0.08) + page, all relative to the height.
        final fit = constraints.maxWidth / (0.72 + 0.08 + aspect);
        // Scaled down while the sizes animate between kinds and formats.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: _build(brightness, aspect, fit < height ? fit : height),
        );
      },
    );
  }

  Widget _build(Brightness brightness, double aspect, double height) {
    final pageWidth = height * aspect;
    final coverWidth = height * 0.72;
    final page = _canvas
        ? template.copyWith(format: PageFormat.a4, orientation: PageOrientation.landscape)
        : template;
    return Semantics(
      label: 'Preview',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Lifted(
            brightness: brightness,
            radius: Radii.cover,
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              width: coverWidth,
              height: height,
              child: NotebookCover(color: coverColor, kind: kind),
            ),
          ),
          SizedBox(width: height * 0.08),
          _Lifted(
            brightness: brightness,
            radius: 3,
            child: AnimatedContainer(
              duration: Motion.medium,
              curve: Motion.standard,
              width: pageWidth,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.topLeft,
                      child: TemplatePreview(template: page, width: pageWidth),
                    ),
                    if (_canvas)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Icon(
                          Icons.all_inclusive_rounded,
                          size: 18,
                          color: Color(coverColor).withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Lifted extends StatelessWidget {
  const _Lifted({required this.brightness, required this.radius, required this.child});

  final Brightness brightness;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: Shadows.high(brightness),
    ),
    child: child,
  );
}
