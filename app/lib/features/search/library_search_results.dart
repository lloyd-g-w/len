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

part 'library_search_rows.dart';

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
              // The label and the count as separate spans (DESIGN §2).
              child: Row(
                children: [
                  const SectionLabel('Pages'),
                  const SizedBox(width: Gaps.sm),
                  Text(
                    count == 1 ? '1 match' : '$count matches',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ],
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
