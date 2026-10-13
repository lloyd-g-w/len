import 'package:flutter/material.dart';

import '../../data/search/search_query.dart';
import '../../ui/app_theme.dart';

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
      fontWeight: FontWeight.w600,
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

/// Colours of search highlights (DESIGN §1): every match is marked like a
/// highlighter on paper, in marker yellow (content, a warmer amber in dark
/// lists); the current match is a state, so it takes the accent: a ruling
/// blue ring around its marker.
abstract final class SearchColors {
  /// Marker yellow for matches (a warmer amber in dark mode).
  static Color match(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? const Color(0xFFFFD43B) : const Color(0xFFFFB020);

  /// The ring around the current match on the page: the light theme's
  /// ruling blue, since pages are light even in dark mode.
  static Color current(ColorScheme scheme) => Tones.light.accent;
}
