import 'package:flutter/material.dart';

import '../../data/search/search_query.dart';

/// A search snippet with its matches emphasised (bold on a tinted
/// background).
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.snippet, {super.key, this.style, this.maxLines = 2});

  /// [text] with the matches of [query] emphasised.
  factory HighlightedText.of(
    String text,
    SearchQuery query, {
    Key? key,
    TextStyle? style,
    int maxLines = 1,
  }) => HighlightedText(
    SearchSnippet(text, query.ranges(text)),
    key: key,
    style: style,
    maxLines: maxLines,
  );

  final SearchSnippet snippet;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? DefaultTextStyle.of(context).style;
    final emphasis = base.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      backgroundColor: SearchColors.match(scheme).withValues(alpha: 0.45),
    );
    final text = snippet.text;
    final spans = <TextSpan>[];
    var at = 0;
    for (final h in snippet.highlights) {
      if (h.start > at) spans.add(TextSpan(text: text.substring(at, h.start)));
      spans.add(TextSpan(text: text.substring(h.start, h.end), style: emphasis));
      at = h.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Colours of search highlights.
abstract final class SearchColors {
  /// Marker yellow for matches (a warmer amber in dark mode).
  static Color match(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? const Color(0xFFFFD43B) : const Color(0xFFFFB020);

  /// The current match: the accent colour.
  static Color current(ColorScheme scheme) => scheme.primary;
}
