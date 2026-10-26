import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'thumbnails/thumbnail_scope.dart';

/// The visual cover of a notebook: a live preview of its content when
/// something is drawn, otherwise a plain cover in its colour.
///
/// Flat colour, no gradient (DESIGN §6.1). Paged notebooks get a darker
/// spine band (in the cover colour beside a preview); canvases a small
/// "∞" tag. Use [NotebookCover.of] to pick up the cached live preview.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.color,
    required this.kind,
    this.preview,
    this.favorite = false,
    this.pending = false,
  });

  /// Cover for [notebook] with its live preview from the [ThumbnailScope];
  /// without the favourite badge when [showFavorite] is false (list rows
  /// show a star of their own).
  static Widget of(Notebook notebook, {Key? key, bool showFavorite = true}) => Builder(
    key: key,
    builder: (context) => NotebookCover(
      color: notebook.coverColor,
      kind: notebook.kind,
      favorite: showFavorite && notebook.favorite,
      preview: ThumbnailScope.previewOf(context, notebook),
      pending: ThumbnailScope.pendingOf(context, notebook),
    ),
  );

  final int color;
  final NotebookKind kind;
  final ui.Image? preview;
  final bool favorite;

  /// The preview isn't rendered yet: a neutral placeholder cross-fades to
  /// the preview or the plain cover, rather than the cover colour flashing
  /// before a thumbnail.
  final bool pending;

  bool get _paged => kind == NotebookKind.paged;

  @override
  Widget build(BuildContext context) {
    final base = Color(color);
    final preview = this.preview;
    const outer = Radius.circular(Radii.sm);
    final radius = _paged
        ? const BorderRadius.horizontal(left: Radius.circular(Radii.xs - 2), right: outer)
        : BorderRadius.circular(Radii.sm);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: Motion.medium,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: pending
                ? ColoredBox(
                    key: const ValueKey('pending'),
                    color: Surfaces.pressed(Theme.of(context).colorScheme),
                  )
                : preview == null
                ? _PlainCover(key: const ValueKey('plain'), color: base)
                : ColoredBox(
                    key: const ValueKey('preview'),
                    color: Palette.paper,
                    child: PreviewImage(image: preview),
                  ),
          ),
          if (_paged && !pending) _Spine(color: base, onPreview: preview != null),
          // A canvas carries its ∞ badge with or without a preview.
          if (!_paged && !pending) const Positioned.fill(child: _CanvasTag()),
          if (favorite) const Positioned(top: 8, right: 8, child: _FavoriteBadge()),
          // Hairline edge so light previews separate from the background.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Palette.paperEdge),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain cover: flat colour, no gradient or sheen (DESIGN §6.1).
class _PlainCover extends StatelessWidget {
  const _PlainCover({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(color: color);
}

/// The bound edge of a paged notebook: a flat band, darker than a plain
/// cover, in the cover colour beside a preview (the cover wraps the paper).
class _Spine extends StatelessWidget {
  const _Spine({required this.color, required this.onPreview});

  final Color color;
  final bool onPreview;

  /// How much darker the band is than a plain cover.
  static const double _shade = 0.18;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.075).clamp(6.0, 16.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: ColoredBox(
              color: onPreview ? color : Color.lerp(color, Tones.light.ink, _shade)!,
            ),
          ),
        );
      },
    );
  }
}

/// Marks a canvas, over its preview or its plain cover: a badge printed on
/// the cover like [_FavoriteBadge], a paper plate with an Ink ∞ (DESIGN §1:
/// badges are neutral; the cover colour stays on the cover), in its
/// bottom-left corner; smaller on small thumbnails, so it never fills them.
class _CanvasTag extends StatelessWidget {
  const _CanvasTag();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.3).clamp(12.0, 24.0);
        final inset = (constraints.maxWidth * 0.06).clamp(2.0, 8.0);
        return Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            width: side,
            height: side,
            margin: EdgeInsets.all(inset),
            decoration: BoxDecoration(
              color: Palette.paper,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: Palette.paperEdge),
            ),
            // Paper stays light in both themes, so its ink is the light Ink.
            child: Icon(
              Symbols.all_inclusive_rounded,
              size: side * 2 / 3,
              color: Tones.of(Brightness.light).ink,
            ),
          ),
        );
      },
    );
  }
}

/// Marks a favourite: like [_CanvasTag], a paper plate printed on the
/// cover with a filled Ink star (DESIGN §1: the star is state on paper, not
/// amber chrome), in the top-right corner.
class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        // A badge printed on the cover: flat, radius xs (DESIGN §3).
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: Palette.paperEdge),
      ),
      // Paper stays light in both themes, so its ink is the light Ink.
      child: Icon(
        Symbols.star_rounded,
        fill: 1,
        size: Glyphs.badge,
        color: Tones.of(Brightness.light).ink,
      ),
    );
  }
}
