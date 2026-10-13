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
          if (!_paged && preview != null)
            Positioned(left: 8, bottom: 8, child: _CanvasTag(color: base)),
          if (!_paged && preview == null && !pending)
            Positioned(
              right: 10,
              bottom: 10,
              child: Icon(
                Symbols.all_inclusive_sharp,
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
            child: ColoredBox(color: onPreview ? color : Color.lerp(color, Colors.black, _shade)!),
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
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.xs)),
      child: const Icon(Symbols.all_inclusive_sharp, size: 14, color: Colors.white),
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
        // A badge printed on the cover: flat, radius xs (DESIGN §3).
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: const Icon(Symbols.star_sharp, fill: 1, size: 16, color: Palette.favourite),
    );
  }
}
