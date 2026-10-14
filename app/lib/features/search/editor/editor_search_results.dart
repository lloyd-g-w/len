part of 'editor_search_bar.dart';

/// The search bar's list of matches.
extension _SearchResults on _EditorSearchBarState {
  Widget _results(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final matches = _c.matches;
    final indexing = _c.search.pdfText.isIndexing;
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Gaps.md),
        child: Text(
          indexing ? 'Reading PDF text…' : 'No matches',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: (height * 0.45).clamp(120, 360)),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        itemBuilder: (context, i) => _MatchTile(
          match: matches[i],
          query: _c.parsedQuery,
          selected: i == _c.current,
          onTap: () => _open(i, compact: compact),
        ),
      ),
    );
  }
}

/// A match in the list: kind, snippet and page.
class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final EditorSearchMatch match;
  final SearchQuery query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? Surfaces.pressed(scheme) : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.xs),
        onTap: onTap,
        // A touch target, like menu rows; longer snippets grow it.
        child: Container(
          constraints: BoxConstraints(minHeight: Targets.menuRowHeight(context)),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SearchHitIcon(hit: match.hit),
              const SizedBox(width: Gaps.sm),
              Expanded(
                // The page sits on the snippet's first line.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: HighlightedText(
                        SearchSnippet.of(
                          match.hit.body,
                          query,
                          around: match.range.start,
                          length: 90,
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: Gaps.sm),
                    if (match.pageIndex != null)
                      Text(
                        hitLocation(match.hit),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
