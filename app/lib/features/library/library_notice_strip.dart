import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import '../../ui/hit_overhang.dart';
import 'library_content.dart';

/// The colour of a [LibraryNotice]'s glyph.
enum NoticeTone {
  /// Something is being lost: a red glyph.
  warning,

  /// Worth knowing: an accent glyph.
  info,
}

/// A calm strip docked above the library (DESIGN §0: chrome is ruled
/// paper): flat on the Board with a hairline under it, a glyph in the
/// tone's colour on the margin column, a title and a sentence or two, with
/// optional [actions] and ✕. No tinted plate.
///
/// With a [shortTitle], phones and short windows get one line instead
/// (R8-7): the glyph, the short title, the first action and ✕, so the
/// notice doesn't push the notebooks off the screen.
class LibraryNotice extends StatelessWidget {
  const LibraryNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.shortTitle,
    this.detail,
    this.actions = const [],
    this.onDismiss,
    this.tone = NoticeTone.warning,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The one-line notice's title on phones and short windows (none: the
  /// whole notice everywhere).
  final String? shortTitle;

  /// Shown selectable under [body] (e.g. a file path to copy).
  final String? detail;

  /// Buttons at the end (e.g. "Keep data"); the one-line notice keeps
  /// the first.
  final List<Widget> actions;

  /// Shows ✕, which calls this.
  final VoidCallback? onDismiss;

  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = tone == NoticeTone.warning ? scheme.error : scheme.primary;
    final compact = Breakpoints.libraryCompact(MediaQuery.sizeOf(context));
    // The library's margins (DESIGN §3): the glyph and the ✕ on the
    // covers' edges.
    final margin = LibraryContent.gutterFor(compact: compact);
    final oneLine = compact ? shortTitle : null;
    final dismiss = onDismiss == null
        ? null
        : IconButton(
            tooltip: 'Dismiss',
            // 48 on touch, 40 with a pointer.
            constraints: BoxConstraints.tightFor(
              width: Targets.barHit(context),
              height: Targets.barHit(context),
            ),
            icon: const Icon(Symbols.close_sharp, size: Glyphs.menu),
            onPressed: onDismiss,
          );
    final glyph = Icon(icon, size: Glyphs.bar, color: tint);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          margin,
          oneLine != null ? 0 : Gaps.md,
          // The one-line notice's ✕ sits in the margin; otherwise the ✕
          // and the actions keep their labels on the content edge (their
          // padding hangs into the margin).
          dismiss == null || oneLine == null ? margin : Gaps.sm,
          oneLine != null ? 0 : (actions.isEmpty ? Gaps.md : Gaps.xs),
        ),
        constraints: BoxConstraints(minHeight: Targets.barHit(context)),
        decoration: BoxDecoration(
          color: Surfaces.chrome(scheme),
          border: Border(bottom: Surfaces.chromeEdge(scheme)),
        ),
        child: oneLine != null
            ? Row(
                children: [
                  glyph,
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Text(
                      oneLine,
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (actions.isNotEmpty) actions.first,
                  ?dismiss,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: Gaps.xxs),
                        child: glyph,
                      ),
                      const SizedBox(width: Gaps.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.labelLarge),
                            const SizedBox(height: Gaps.xxs),
                            Text(
                              body,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (detail case final detail?) ...[
                              const SizedBox(height: Gaps.xxs),
                              SelectableText(detail, style: theme.textTheme.bodySmall),
                            ],
                          ],
                        ),
                      ),
                      if (dismiss != null) _onGlyphLine(context, dismiss),
                    ],
                  ),
                  // The actions end on the ✕'s edge, under it: one right
                  // edge for everything at the end of the notice.
                  if (actions.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: HitOverhang(
                        overhang: const EdgeInsetsDirectional.only(end: Gaps.md),
                        child: Wrap(spacing: Gaps.xs, children: actions),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// [dismiss] centred on the glyph's line (the title's) with its glyph
  /// on the content edge: its touch target hangs into the notice's top
  /// padding and the margin instead of pushing the ✕ down and in.
  static Widget _onGlyphLine(BuildContext context, Widget dismiss) {
    final spare = Targets.barHit(context) - Glyphs.bar;
    return HitOverhang(
      overhang: EdgeInsetsDirectional.only(
        top: spare / 2 - Gaps.xxs,
        bottom: spare / 2 + Gaps.xxs,
        end: spare / 2,
      ),
      child: dismiss,
    );
  }
}
