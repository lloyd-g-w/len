part of 'library_search_results.dart';

/// One notebook's matches: its cover and title, then a row per match.
class _NotebookResults extends StatefulWidget {
  const _NotebookResults({
    super.key,
    required this.group,
    required this.query,
    required this.onOpen,
  });

  final NotebookHits group;
  final SearchQuery query;
  final OpenSearchResult onOpen;

  @override
  State<_NotebookResults> createState() => _NotebookResultsState();
}

class _NotebookResultsState extends State<_NotebookResults> {
  bool _expanded = false;

  /// Matches shown before "Show all".
  static const _collapsed = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = widget.group;
    final notebook = group.notebook;
    final hits = _expanded ? group.content : group.content.take(_collapsed).toList();
    final hidden = group.content.length - hits.length;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => widget.onOpen(context, notebook, null),
            borderRadius: BorderRadius.circular(Radii.xs),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.sm, Gaps.sm, Gaps.sm, Gaps.xs),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      boxShadow: Shadows.low(theme.brightness),
                    ),
                    child: SizedBox(
                      width: 28,
                      height: 28 / 0.72,
                      child: NotebookCover.of(notebook, showFavorite: false),
                    ),
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: HighlightedText.of(
                      notebook.title,
                      group.titleMatches ? widget.query : SearchQuery(''),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  // Rows below show a single match.
                  if (group.content.length > 1)
                    Text('${group.content.length} matches', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          for (final hit in hits)
            _HitRow(
              hit: hit,
              query: widget.query,
              onTap: () => widget.onOpen(context, notebook, hit),
            ),
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: Gaps.xxl + Gaps.xs),
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = true),
                  icon: const Icon(Symbols.expand_more_rounded, size: Glyphs.menu),
                  label: Text('Show $hidden more'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A match: page number, kind and snippet.
class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.query, required this.onTap});

  final SearchHit hit;
  final SearchQuery query;
  final VoidCallback onTap;

  /// Room for "Page 12" or "Canvas" before the snippet.
  static const double _locationWidth = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 28, child: SearchHitIcon(hit: hit)),
            const SizedBox(width: Gaps.md),
            // Where the match is, as a plain label in a column of its own
            // (no plate), so snippets line up.
            Container(
              constraints: BoxConstraints(
                minWidth: MediaQuery.textScalerOf(context).scale(_locationWidth),
              ),
              // On the snippet's first line (16-dp label, 20-dp line).
              padding: const EdgeInsets.only(top: Gaps.xxs),
              child: Text(
                hitLocation(hit),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: Gaps.sm),
            Expanded(
              child: HighlightedText(
                SearchSnippet.of(hit.body, query),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The kind of a hit: a text box or PDF text.
class SearchHitIcon extends StatelessWidget {
  const SearchHitIcon({super.key, required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: switch (hit.kind) {
      SearchHitKind.pdf => 'PDF text',
      SearchHitKind.handwriting => 'Handwriting',
      _ => 'Text box',
    },
    child: Icon(
      switch (hit.kind) {
        SearchHitKind.pdf => Symbols.picture_as_pdf_rounded,
        SearchHitKind.handwriting => Symbols.draw_rounded,
        _ => Symbols.text_fields_rounded,
      },
      size: Glyphs.menu,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
