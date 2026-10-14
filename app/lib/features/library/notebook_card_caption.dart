part of 'notebook_card.dart';

/// The caption area of a [NotebookCard].
extension _CardCaption on _NotebookCardState {
  /// The title (beside the ⋯) and the caption under the cover.
  Widget _caption(BuildContext context, {required bool showMore}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
      child: Padding(
        padding: const EdgeInsets.only(top: Gaps.sm),
        // The ⋯ sits beside the title only; the caption below takes
        // the full width (it would truncate early at large text).
        child: Stack(
          children: [
            // The title is part of the target too; the cover
            // says it to screen readers.
            Positioned.fill(
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: _tap,
                onSecondaryTapUp: (d) => unawaited(_showMenu(at: d.globalPosition)),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(left: Gaps.xxs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: _selecting ? 0 : NotebookCard._moreRoom),
                          child: _CardTitle(_notebook.title),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (widget.recordings > 0) ...[
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(
                                    Symbols.mic_sharp,
                                    size: MediaQuery.textScalerOf(context)
                                        .scale(theme.textTheme.bodySmall?.fontSize ?? 0),
                                    color: theme.textTheme.bodySmall?.color,
                                    semanticLabel: widget.recordings == 1
                                        ? '1 recording'
                                        : '${widget.recordings} recordings',
                                  ),
                                ),
                                const TextSpan(text: ' '),
                              ],
                              TextSpan(text: widget.subtitle),
                            ],
                          ),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_selecting)
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: showMore ? 1 : 0,
                  duration: Motion.fast,
                  // Reachable by screen readers while hidden.
                  alwaysIncludeSemantics: true,
                  // A 48-dp target on touch; the glyph keeps its
                  // place beside the title's first line.
                  child: SizedBox(
                    width: Targets.of(context, NotebookCard._moreWidth),
                    height: Targets.of(context, NotebookCard._moreHeight),
                    child: Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'More',
                        alignment: Alignment.topRight,
                        // Centred on the title's first line (20 dp).
                        padding: EdgeInsets.only(
                          top: math.max(
                            0,
                            (MediaQuery.textScalerOf(context).scale(20) - Glyphs.bar) / 2,
                          ),
                        ),
                        iconSize: Glyphs.bar,
                        color: scheme.onSurfaceVariant,
                        // Reachable by keyboard while hidden.
                        icon: const Icon(Symbols.more_horiz_sharp),
                        onPressed: () => unawaited(_showMenu(anchor: anchor)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desaturates and fades [cover] (trashed notebooks).
Widget fadedCover(Widget cover) => Opacity(
  opacity: 0.8,
  child: ColorFiltered(
    colorFilter: const ColorFilter.matrix([
      0.5, 0.4, 0.1, 0, 20, //
      0.2, 0.7, 0.1, 0, 20, //
      0.2, 0.4, 0.4, 0, 20, //
      0, 0, 0, 1, 0, //
    ]),
    child: cover,
  ),
);

/// A card's title in up to two lines, broken only between words: a word
/// wider than the line (narrow covers in a short window) ends in an
/// ellipsis on one line rather than splitting ("Whitebo / ard").
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        );
        final splits = title.split(' ').any((word) {
          painter
            ..text = TextSpan(text: word, style: style)
            ..layout();
          return painter.width > constraints.maxWidth;
        });
        painter.dispose();
        return Text(title, style: style, maxLines: splits ? 1 : 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
