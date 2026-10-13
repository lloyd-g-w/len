import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/search/search_index.dart';
import '../../data/search/search_query.dart';
import '../../data/search/search_service.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';
import '../library/notebook_cover.dart';
import 'highlighted_text.dart';
import 'search_groups.dart';

/// Opens [notebook] in the editor; with a [hit], at that result.
typedef OpenSearchResult = void Function(BuildContext context, Notebook notebook, SearchHit? hit);

/// Asks the editor to show [hit] for [query], then opens [notebook] with
/// [open] (the library's usual way of opening a notebook).
Future<void> openSearchResult(
  BuildContext context,
  Notebook notebook,
  SearchHit? hit, {
  required String query,
  required Future<void> Function(BuildContext, Notebook) open,
}) {
  if (hit != null) {
    AppScope.read(context).search
        .requestJump(SearchJump(notebookId: notebook.id, query: query, hit: hit));
  }
  return open(context, notebook);
}

/// The library's full-text results as a sliver: text boxes and PDF pages
/// matching [query], grouped by notebook, with page numbers and
/// highlighted snippets. Shows [whenEmpty] if nothing matches.
class LibrarySearchResults extends StatefulWidget {
  const LibrarySearchResults({
    super.key,
    required this.query,
    required this.onOpen,
    this.padding = EdgeInsets.zero,
    this.whenEmpty,
  });

  final String query;
  final OpenSearchResult onOpen;
  final EdgeInsets padding;
  final Widget? whenEmpty;

  @override
  State<LibrarySearchResults> createState() => _LibrarySearchResultsState();
}

class _LibrarySearchResultsState extends State<LibrarySearchResults> {
  late final AppServices _services = AppScope.read(context);
  List<NotebookHits> _groups = const [];
  late SearchQuery _query;
  Timer? _debounce;
  StreamSubscription<Object?>? _remote;

  /// Delay before re-running a search while typing.
  static const _debounceDelay = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _services.search.addListener(_schedule);
    _remote = _services.sync.remoteChanges.listen((_) => _schedule());
    _refresh();
  }

  @override
  void didUpdateWidget(LibrarySearchResults old) {
    super.didUpdateWidget(old);
    // Same query too: the library rebuilds after a notebook was edited.
    _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_remote?.cancel());
    _services.search.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(_refresh);
    });
  }

  void _refresh() {
    _query = SearchQuery(widget.query);
    final hits = _services.search.search(widget.query);
    _groups = groupByNotebook(
      hits,
      _services.notebooks.get,
    ).where((g) => g.content.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indexing = _services.search.pdfText.isIndexing;
    if (_groups.isEmpty) {
      return SliverMainAxisGroup(
        slivers: [
          if (indexing) SliverPadding(padding: widget.padding, sliver: _indexingNote(theme)),
          if (widget.whenEmpty case final empty?)
            SliverFillRemaining(hasScrollBody: false, child: empty)
          else
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
    }
    final count = _groups.fold(0, (n, g) => n + g.content.length);
    return SliverPadding(
      padding: widget.padding,
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.xxs, Gaps.xl, 0, Gaps.md),
              child: Text(
                'Pages · ${count == 1 ? '1 match' : '$count matches'}',
                style: SectionLabel.style(context),
              ),
            ),
          ),
          if (indexing) _indexingNote(theme),
          SliverList.separated(
            itemCount: _groups.length,
            // Flat rows, groups split by hairlines (REDESIGN §3).
            separatorBuilder: (_, _) =>
                Divider(height: Gaps.lg, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, i) => _NotebookResults(
              key: ValueKey(_groups[i].notebook.id),
              group: _groups[i],
              query: _query,
              onOpen: widget.onOpen,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)), // Clear of the FAB.
        ],
      ),
    );
  }

  Widget _indexingNote(ThemeData theme) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
      child: Row(
        children: [
          const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Gaps.sm),
          Text('Reading PDF text…', style: theme.textTheme.bodySmall),
        ],
      ),
    ),
  );
}

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
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.sm, Gaps.sm, Gaps.sm, Gaps.xs),
              child: Row(
                children: [
                  SizedBox(width: 28, height: 28 / 0.72, child: NotebookCover.of(notebook)),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 28, child: SearchHitIcon(hit: hit)),
            const SizedBox(width: Gaps.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                hitLocation(hit),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
