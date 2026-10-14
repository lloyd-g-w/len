import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/search/search_query.dart';
import '../../../ui/app_theme.dart';
import '../highlighted_text.dart';
import '../library_search_results.dart' show SearchHitIcon;
import '../search_groups.dart';
import 'editor_search_controller.dart';

part 'editor_search_results.dart';

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
      // A slip over the page (lifted, like a popover), not chrome. The text
      // editing shortcuts are restated here, below the editor's own: else
      // the editor's Backspace, arrows, Ctrl+A and Ctrl+Z bindings would
      // swallow those keys before they reach the field.
      child: DefaultTextEditingShortcuts(
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
      ),
    );
  }

  Widget _fieldRow(BuildContext context, {required bool showList, required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = _c.matches.length;
    final hasMatches = count > 0;
    // Nothing while the list below says "No matches"; one format everywhere.
    final counter = _c.query.trim().isEmpty || (count == 0 && showList)
        ? ''
        : _c.current >= 0
        ? '${_c.current + 1} of $count'
        : (count == 1 ? '1 match' : '$count matches');
    final counterStyle = theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures);
    // Compact buttons save room on narrow windows, but not under fingers
    // (they would drop below 48 dp).
    final density = compact && !Targets.touchFirst ? VisualDensity.compact : null;
    final field = TextField(
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
    );
    final steps = [
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
      // On: the ink plate and the filled glyph, like a selected tool.
      IconButton(
        tooltip: showList ? 'Hide results' : 'Show results',
        visualDensity: density,
        isSelected: showList,
        onPressed: () => setState(() => _showList = !showList),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Surfaces.selected(scheme) : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? null
                : states.contains(WidgetState.selected)
                ? scheme.onSurface
                : null,
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xs))),
          ),
        ),
        icon: const Icon(Symbols.list_sharp),
        selectedIcon: const Icon(Symbols.list_sharp, fill: 1),
      ),
    ];
    final close = IconButton(
      tooltip: 'Close (Esc)',
      visualDensity: density,
      onPressed: _close,
      icon: const Icon(Symbols.close_sharp),
    );
    final leading = [
      const SizedBox(width: Gaps.sm),
      Icon(Symbols.search_sharp, size: Glyphs.bar, color: scheme.onSurfaceVariant),
      const SizedBox(width: Gaps.sm),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // The field comes first: when the counter and the buttons would
        // squeeze it (large text on a phone), they move to a second line.
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          text: TextSpan(text: counter, style: counterStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final counterWidth = painter.width;
        painter.dispose();
        const buttons = 4 * Targets.touch, lead = Gaps.sm * 2 + Glyphs.bar;
        final room = constraints.maxWidth - lead - buttons - counterWidth;
        if (room >= scaler.scale(_minField)) {
          return Row(
            children: [
              ...leading,
              Expanded(child: field),
              Text(counter, style: counterStyle),
              ...steps,
              close,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ...leading,
                Expanded(child: field),
                close,
              ],
            ),
            Row(
              children: [
                const SizedBox(width: Gaps.sm),
                Expanded(child: Text(counter, style: counterStyle)),
                ...steps,
              ],
            ),
          ],
        );
      },
    );
  }

  /// The field's least width (at 1× text) before the bar takes two lines.
  static const double _minField = 80;
}
