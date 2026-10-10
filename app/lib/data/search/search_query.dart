/// A parsed search query: the words typed, each matched as a word prefix,
/// ignoring case and accents — the same rules the FTS5 index applies
/// (`unicode61 remove_diacritics 2` with `"term"*`), so ranges found here
/// in Dart (snippets, in-notebook matches) agree with what the index found.
class SearchQuery {
  SearchQuery._(this.raw, this.terms);

  /// Parses [input]; words are runs of letters and digits.
  factory SearchQuery(String input) {
    final folded = SearchText.fold(input);
    final terms = <String>{for (final m in _word.allMatches(folded)) m.group(0)!}.toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // Longest first.
    return SearchQuery._(input, terms);
  }

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  final String raw;

  /// Folded, distinct words (longest first).
  final List<String> terms;

  bool get isEmpty => terms.isEmpty;

  /// The FTS5 MATCH expression: every term as a prefix (implicit AND).
  String get ftsExpression => terms.map((t) => '"$t"*').join(' ');

  /// `LIKE` patterns (one per term, all must match) for databases without
  /// FTS5; `\` escapes.
  List<String> get likePatterns => [
    for (final t in terms) '%${t.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}')}%',
  ];

  /// Whether every term occurs in [text] as a word prefix.
  bool matches(String text) {
    if (isEmpty) return false;
    final folded = SearchText.fold(text);
    return terms.every((t) => _occurrences(folded, t).isNotEmpty);
  }

  /// Ranges of [text] (sorted, non-overlapping) where any term starts a
  /// word; each range covers the matched prefix.
  List<({int start, int end})> ranges(String text) {
    if (isEmpty) return const [];
    final folded = SearchText.fold(text);
    final found = <({int start, int end})>[
      for (final t in terms)
        for (final start in _occurrences(folded, t)) (start: start, end: start + t.length),
    ]..sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
    final merged = <({int start, int end})>[];
    for (final r in found) {
      if (merged.isNotEmpty && r.start < merged.last.end) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: r.end > last.end ? r.end : last.end));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// Start offsets of [term] in [folded] at word starts.
  static List<int> _occurrences(String folded, String term) {
    final result = <int>[];
    var i = folded.indexOf(term);
    while (i != -1) {
      if (i == 0 || !SearchText.isWordChar(folded.codeUnitAt(i - 1))) result.add(i);
      i = folded.indexOf(term, i + 1);
    }
    return result;
  }
}

/// A short excerpt of a longer text around its first match, with the
/// matches to emphasise (offsets into [text]).
class SearchSnippet {
  const SearchSnippet(this.text, this.highlights);

  final String text;
  final List<({int start, int end})> highlights;

  /// The excerpt of [body] around the first match of [query] (or around
  /// offset [around] of [body]): about [context] characters before it, up
  /// to [length] in all, whitespace collapsed, with `…` where text was cut.
  factory SearchSnippet.of(
    String body,
    SearchQuery query, {
    int context = 32,
    int length = 120,
    int? around,
  }) {
    final (text, offsets) = _collapse(body);
    final ranges = query.ranges(text);
    final anchor = around != null
        ? offsets[around.clamp(0, body.length)]
        : (ranges.isEmpty ? 0 : ranges.first.start);
    var start = (anchor - context).clamp(0, text.length);
    // Start at a word boundary.
    if (start > 0) {
      final space = text.lastIndexOf(' ', start);
      start = space == -1 || anchor - space > context + 16 ? start : space + 1;
    }
    var end = (start + length).clamp(0, text.length);
    if (end < text.length) {
      final space = text.lastIndexOf(' ', end);
      if (space > anchor) end = space;
    }
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    final shift = prefix.length - start;
    return SearchSnippet('$prefix${text.substring(start, end)}$suffix', [
      for (final r in ranges)
        if (r.start >= start && r.end <= end) (start: r.start + shift, end: r.end + shift),
    ]);
  }

  /// [body] with whitespace runs collapsed to one space and trimmed, and
  /// for each offset of [body] (and its end) the matching offset in it.
  static (String, List<int>) _collapse(String body) {
    final out = StringBuffer();
    final offsets = List<int>.filled(body.length + 1, 0);
    var pendingSpace = false;
    for (var i = 0; i < body.length; i++) {
      final c = body.codeUnitAt(i);
      if (c == 32 || (c >= 9 && c <= 13) || c == 0xA0) {
        pendingSpace = out.isNotEmpty;
        offsets[i] = out.length;
      } else {
        if (pendingSpace) out.write(' ');
        pendingSpace = false;
        offsets[i] = out.length;
        out.writeCharCode(c);
      }
    }
    offsets[body.length] = out.length;
    return (out.toString(), offsets);
  }
}

/// Case and accent folding that keeps every offset (one UTF-16 unit in,
/// one out), so ranges found in folded text apply to the original.
abstract final class SearchText {
  static final Map<int, int> _fold = _buildFoldTable();

  /// Lower-cases [text] and strips accents from Latin letters.
  static String fold(String text) {
    final lower = text.toLowerCase();
    if (lower.length != text.length) return _foldUnits(text); // e.g. 'İ'.
    return _foldUnits(lower);
  }

  static String _foldUnits(String text) {
    final units = text.codeUnits;
    final out = List<int>.filled(units.length, 0);
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      final lowered = c < 128
          ? (c >= 65 && c <= 90 ? c + 32 : c)
          : String.fromCharCode(c).toLowerCase().codeUnitAt(0);
      out[i] = _fold[lowered] ?? lowered;
    }
    return String.fromCharCodes(out);
  }

  /// Whether UTF-16 unit [c] belongs to a word (letters, digits, and
  /// surrogates — characters outside the BMP are treated as letters).
  static bool isWordChar(int c) {
    if (c < 128) {
      return (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90);
    }
    if (c >= 0xD800 && c <= 0xDFFF) return true;
    return _letterOrDigit.hasMatch(String.fromCharCode(c));
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

  static Map<int, int> _buildFoldTable() {
    const groups = {
      'a': 'àáâãäåāăąǎ',
      'c': 'çćĉċč',
      'd': 'ďđ',
      'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ',
      'h': 'ĥħ',
      'i': 'ìíîïĩīĭįı',
      'j': 'ĵ',
      'k': 'ķ',
      'l': 'ĺļľŀł',
      'n': 'ñńņňŉ',
      'o': 'òóôõöøōŏőǒ',
      'r': 'ŕŗř',
      's': 'śŝşšș',
      't': 'ţťŧț',
      'u': 'ùúûüũūŭůűųǔ',
      'w': 'ŵ',
      'y': 'ýÿŷ',
      'z': 'źżž',
    };
    return {
      for (final MapEntry(:key, :value) in groups.entries)
        for (final c in value.codeUnits) c: key.codeUnitAt(0),
    };
  }
}
