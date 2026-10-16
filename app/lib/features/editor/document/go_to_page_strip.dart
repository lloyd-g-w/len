import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import 'go_to_page_dialog.dart';
import 'page_backgrounds.dart';
import 'page_thumbnail.dart';

/// One page in Go to page's strip: its thumbnail (ringed while the field
/// names it) and its number, with its PDF page's number beside it when that
/// differs ([pdfLabel], UX_AUDIT R18-5).
class StripPage extends StatelessWidget {
  const StripPage({
    super.key,
    required this.page,
    required this.number,
    this.pdfLabel,
    required this.target,
    required this.cache,
    required this.backgrounds,
    required this.onTap,
  });

  final NotebookPage page;
  final int number;

  /// "Slide 23" / "PDF p. 23", or null.
  final String? pdfLabel;
  final bool target;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = GoToPageDialog.thumbWidth(page);
    return Semantics(
      button: true,
      selected: target,
      label:
          'Page $number${pdfLabel == null ? '' : ', $pdfLabel'}'
          '${page.bookmarked ? ', bookmarked' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('go-to-page-$number'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xxs),
          child: Column(
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                width: width,
                height: GoToPageDialog.thumbHeight,
                // Page miniatures are square; the chosen one gets the 2-dp
                // accent ring (DESIGN §7).
                decoration: BoxDecoration(
                  border: Border.all(
                    color: target ? scheme.primary : scheme.outlineVariant,
                    width: target ? Hairline.rule : Hairline.width,
                  ),
                ),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        child: SizedBox(
                          width: width,
                          height: width * page.height / page.width,
                          child: PageThumbnail(page: page, cache: cache, backgrounds: backgrounds),
                        ),
                      ),
                      if (page.bookmarked)
                        Positioned(
                          top: 0,
                          right: Gaps.xs,
                          child: Icon(
                            Symbols.bookmark_sharp,
                            fill: 1,
                            size: Glyphs.badge,
                            color: Palette.bookmark,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gaps.xs),
              SizedBox(
                width: width,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$number',
                        style: TextStyle(
                          color: target ? scheme.onSurface : null,
                          fontWeight: target ? AppTheme.currentWeight : null,
                        ),
                      ),
                      if (pdfLabel != null) TextSpan(text: ' · $pdfLabel'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
