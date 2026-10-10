import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/cover_style.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'cover_pattern_painter.dart';
import 'thumbnails/thumbnail_scope.dart';

/// The visual cover of a notebook: a live preview of its content when
/// something is drawn, otherwise a coloured, patterned cover.
///
/// Paged notebooks get a bound spine in the cover colour; canvases a small
/// "∞" tag. Use [NotebookCover.of] to pick up the cached live preview.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.color,
    required this.style,
    required this.kind,
    this.preview,
    this.favorite = false,
  });

  /// Cover for [notebook] with its live preview from the [ThumbnailScope].
  static Widget of(Notebook notebook, {Key? key}) => Builder(
    key: key,
    builder: (context) => NotebookCover(
      color: notebook.coverColor,
      style: notebook.coverStyle,
      kind: notebook.kind,
      favorite: notebook.favorite,
      preview: ThumbnailScope.previewOf(context, notebook),
    ),
  );

  final int color;
  final CoverStyle style;
  final NotebookKind kind;
  final ui.Image? preview;
  final bool favorite;

  bool get _paged => kind == NotebookKind.paged;

  @override
  Widget build(BuildContext context) {
    final base = Color(color);
    final preview = this.preview;
    const outer = Radius.circular(Radii.cover);
    final radius = _paged
        ? const BorderRadius.horizontal(left: Radius.circular(Radii.xs - 2), right: outer)
        : BorderRadius.circular(Radii.cover);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: Motion.medium,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: preview == null
                ? _PlainCover(
                    key: const ValueKey('plain'),
                    color: base,
                    style: style,
                    paged: _paged,
                  )
                : ColoredBox(
                    key: const ValueKey('preview'),
                    color: Palette.paper,
                    child: PreviewImage(image: preview),
                  ),
          ),
          if (_paged) _Spine(color: base, onPreview: preview != null),
          if (!_paged && preview != null)
            Positioned(left: 8, bottom: 8, child: _CanvasTag(color: base)),
          if (!_paged && preview == null)
            Positioned(
              right: 10,
              bottom: 10,
              child: Icon(
                Icons.all_inclusive_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 20,
              ),
            ),
          if (favorite) const Positioned(top: 8, right: 8, child: _FavoriteBadge()),
          // Hairline edge so light previews separate from the background.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainCover extends StatelessWidget {
  const _PlainCover({super.key, required this.color, required this.style, required this.paged});

  final Color color;
  final CoverStyle style;
  final bool paged;

  @override
  Widget build(BuildContext context) {
    // Canvases without a chosen pattern hint at an endless dot grid.
    final pattern = !paged && style == CoverStyle.plain ? CoverStyle.dots : style;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.14)!, Color.lerp(color, Colors.black, 0.16)!],
        ),
      ),
      child: CustomPaint(
        painter: CoverPatternPainter(pattern, opacity: pattern == style ? 0.16 : 0.12),
        // A soft sheen from the top, like light on a laminated cover.
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bound edge of a paged notebook.
class _Spine extends StatelessWidget {
  const _Spine({required this.color, required this.onPreview});

  final Color color;
  final bool onPreview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.075).clamp(6.0, 16.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: width,
                decoration: BoxDecoration(
                  color: onPreview ? color : Colors.black.withValues(alpha: 0.14),
                  gradient: onPreview
                      ? LinearGradient(colors: [Color.lerp(color, Colors.black, 0.12)!, color])
                      : null,
                ),
              ),
              // Highlight on a cover, a soft fold shadow on paper.
              Container(
                width: onPreview ? 8 : 1.5,
                decoration: BoxDecoration(
                  gradient: onPreview
                      ? LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.14),
                            Colors.black.withValues(alpha: 0),
                          ],
                        )
                      : null,
                  color: onPreview ? null : Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CanvasTag extends StatelessWidget {
  const _CanvasTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: const Icon(Icons.all_inclusive_rounded, size: 14, color: Colors.white),
    );
  }
}

class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5A524)),
    );
  }
}
