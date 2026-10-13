import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/search/search_query.dart';
import '../../../ui/app_theme.dart';
import '../highlighted_text.dart';
import '../library_search_results.dart' show SearchHitIcon;
import '../search_groups.dart';
import 'editor_search_controller.dart';

/// The in-notebook search bar: a field, the match count, previous / next,
/// and a list of matches with page numbers and snippets.
///
/// Keys: Enter (the field's submit action) / F3 next, Shift+Enter / Shift+F3 previous, Esc closes.
class EditorSearchBar extends StatefulWidget {
  const EditorSearchBar({super.key, required this.controller, required this.onClose});

  final EditorSearchController controller;

  /// Called after the bar closed (e.g. to give focus back to the canvas).
  final VoidCallback onClose;

  @override
  State<EditorSearchBar> createState() => _EditorSearchBarState();
}

class _EditorSearchBarState extends State<EditorSearchBar> {
  late final TextEditingController _text = TextEditingController(text: _c.query);
  final FocusNode _focus = FocusNode(debugLabel: 'Notebook search');

  /// Whether the match list shows; null: only on wider screens.
  bool? _showList;
  late int _focusRequests = _c.focusRequests;

  EditorSearchController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusField());
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync() {
    if (_text.text != _c.query) {
      _text.value = TextEditingValue(
        text: _c.query,
        selection: TextSelection.collapsed(offset: _c.query.length),
      );
    }
    if (_c.focusRequests != _focusRequests) {
      _focusRequests = _c.focusRequests;
      _focusField();
    }
  }

  void _focusField() {
    if (!mounted) return;
    _focus.requestFocus();
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
  }

  void _close() {
    _c.close();
    widget.onClose();
  }

  void _open(int index, {required bool compact}) {
    _c.select(index);
    if (compact) setState(() => _showList = false); // Let the page show.
  }

  bool get _compact => MediaQuery.sizeOf(context).width < 600;

  /// Next / previous match. Phones fold the list away first: it covers
  /// half the screen, and the top of the first page can't scroll below it.
  void _step(bool forward) {
    if (_compact && _showList == true) setState(() => _showList = false);
    forward ? _c.next() : _c.previous();
  }

  void _next() => _step(true);
  void _previous() => _step(false);

  @override
  Widget build(BuildContext context) {
    final compact = _compact;
    final showList = _showList ?? !compact;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f3): _next,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): _previous,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): _previous,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _focusField,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _focusField,
      },
      // A slip over the page (lifted, like a popover), not chrome.
      child: OverlaySurface(
        child: Padding(
          padding: const EdgeInsets.all(Gaps.xs),
          child: ListenableBuilder(
            listenable: Listenable.merge([_c, _c.search]),
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldRow(context, showList: showList, compact: compact),
                if (showList && _c.query.trim().isNotEmpty) ...[
                  const Divider(height: Gaps.sm),
                  _results(context, compact: compact),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(BuildContext context, {required bool showList, required bool compact}) {
    final theme = Theme.of(context);
    final count = _c.matches.length;
    final hasMatches = count > 0;
    // Nothing while the list below says "No matches"; one format everywhere.
    final counter = _c.query.trim().isEmpty || (count == 0 && showList)
        ? ''
        : _c.current >= 0
        ? '${_c.current + 1} of $count'
        : (count == 1 ? '1 match' : '$count matches');
    // Compact buttons save room on narrow windows, but not under fingers
    // (they would drop below 48 dp).
    final density = compact && !Targets.touchFirst ? VisualDensity.compact : null;
    return Row(
      children: [
        const SizedBox(width: Gaps.sm),
        Icon(Symbols.search_sharp, size: Glyphs.bar, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: Gaps.sm),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: _c.setQuery,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              _next();
              _focus.requestFocus(); // Keep typing / pressing Enter.
            },
            decoration: const InputDecoration(
              hintText: 'Search this notebook',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
            ),
          ),
        ),
        Text(
          counter,
          style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
        ),
        IconButton(
          tooltip: 'Previous (Shift+Enter)',
          visualDensity: density,
          onPressed: hasMatches ? _previous : null,
          icon: const Icon(Symbols.keyboard_arrow_up_sharp),
        ),
        IconButton(
          tooltip: 'Next (Enter)',
          visualDensity: density,
          onPressed: hasMatches ? _next : null,
          icon: const Icon(Symbols.keyboard_arrow_down_sharp),
        ),
        IconButton(
          tooltip: showList ? 'Hide results' : 'Show results',
          visualDensity: density,
          isSelected: showList,
          onPressed: () => setState(() => _showList = !showList),
          icon: const Icon(Symbols.list_sharp),
        ),
        IconButton(
          tooltip: 'Close (Esc)',
          visualDensity: density,
          onPressed: _close,
          icon: const Icon(Symbols.close_sharp),
        ),
      ],
    );
  }

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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SearchHitIcon(hit: match.hit),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: HighlightedText(
                  SearchSnippet.of(match.hit.body, query, around: match.range.start, length: 90),
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
      ),
    );
  }
}
