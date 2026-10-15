/// A parsed search query: the words typed, each matched as a word prefix,
/// ignoring case and accents — the same rules the FTS5 index applies
/// (`unicode61 remove_diacritics 2` with `"term"*`), so ranges found here
/// in Dart (snippets, in-notebook matches) agree with what the index found.
class SearchQuery {
  SearchQuery._(this.raw, this.terms, this._written);

  /// Parses [input]; words are runs of letters and digits. Combining marks
  /// (decomposed accents: `e` + U+0301, Indic vowel signs, Thai marks)
  /// belong to their word and are dropped from [terms].
  factory SearchQuery(String input) {
    final folded = SearchText.fold(input);
    final written = <String, String>{};
    for (final m in _word.allMatches(folded)) {
      final word = m.group(0)!;
      final t = word.replaceAll(_mark, '');
      if (t.isNotEmpty) written.putIfAbsent(t, () => word);
    }
    final terms = written.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    return SearchQuery._(input, terms, written); // Longest first.
  }

  static final _word = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);
  static final _mark = RegExp(r'\p{M}', unicode: true);

  final String raw;

  /// Folded, distinct words (longest first).
  final List<String> terms;

  bool get isEmpty => terms.isEmpty;

  /// Each term as typed, marks kept.
  final Map<String, String> _written;

  /// The FTS5 MATCH expression: every term as a prefix (implicit AND). The
  /// words go as typed: the index's tokenizer drops Latin accents, but
  /// splits words at other marks (Indic vowel signs, Thai), so `"गणित"*`
  /// becomes the phrase it indexed.
  String get ftsExpression => terms.map((t) => '"${_written[t]}"*').join(' ');

  /// `LIKE` patterns (one per term, all must match) for databases without
  /// FTS5; `\` escapes.
  List<String> get likePatterns => [
    for (final t in terms) '%${t.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}')}%',
  ];

  /// Whether every term occurs in [text] as a word prefix. With
  /// [inUnspacedRuns], a term in a script written without spaces (Chinese,
  /// Japanese, Thai, …) may also start inside a run of that script, where
  /// words have no visible start (titles; the index can't do this).
  bool matches(String text, {bool inUnspacedRuns = false}) {
    if (isEmpty) return false;
    final (folded, _) = _bare(text);
    return terms.every((t) => _occurrences(folded, t, inUnspacedRuns).isNotEmpty);
  }

  /// Ranges of [text] (sorted, non-overlapping) where any term starts a
  /// word; each range covers the matched prefix (and the combining marks
  /// on its last letter).
  List<({int start, int end})> ranges(String text) {
    if (isEmpty) return const [];
    final (folded, offsets) = _bare(text);
    int endOf(int bareEnd) {
      var end = offsets[bareEnd - 1] + 1;
      while (end < text.length && _mark.hasMatch(text[end])) {
        end++;
      }
      return end;
    }

    final found = <({int start, int end})>[
      for (final t in terms)
        for (final start in _occurrences(folded, t, false))
          (start: offsets[start], end: endOf(start + t.length)),
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

  /// [text] folded with its combining marks dropped, as terms are (so
  /// decomposed accents, Indic vowel signs and Thai marks match), and for
  /// each of its units the offset in [text].
  static (String, List<int>) _bare(String text) {
    final folded = SearchText.fold(text);
    if (!_mark.hasMatch(folded)) return (folded, List<int>.generate(folded.length, (i) => i));
    final out = StringBuffer();
    final offsets = <int>[];
    for (var i = 0; i < folded.length; i++) {
      final c = folded[i];
      if (_mark.hasMatch(c)) continue;
      out.write(c);
      offsets.add(i);
    }
    return (out.toString(), offsets);
  }

  /// Start offsets of [term] in [folded] at word starts (or, with
  /// [inUnspacedRuns], inside a run of a script written without spaces).
  static List<int> _occurrences(String folded, String term, bool inUnspacedRuns) {
    final result = <int>[];
    final unspaced = inUnspacedRuns && _unspaced.hasMatch(term[0]);
    var i = folded.indexOf(term);
    while (i != -1) {
      if (i == 0 || !SearchText.isWordChar(folded.codeUnitAt(i - 1))) {
        result.add(i);
      } else if (unspaced && _unspaced.hasMatch(folded[i - 1])) {
        result.add(i);
      }
      i = folded.indexOf(term, i + 1);
    }
    return result;
  }

  /// Scripts written without spaces between words.
  static final _unspaced = RegExp(
    r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}'
    r'\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}\u30FC]',
    unicode: true,
  );
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

  /// Letters with a decomposable accent only, as FTS5's `unicode61
  /// remove_diacritics 2` folds them: it keeps letters like ø, ł, đ, ħ,
  /// ı, ŧ, so folding them here would make queries (`kobenhavn` for
  /// København) that the index never matches.
  static Map<int, int> _buildFoldTable() {
    const groups = {
      'a': 'àáâãäåāăąǎ',
      'c': 'çćĉċč',
      'd': 'ď',
      'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ',
      'h': 'ĥ',
      'i': 'ìíîïĩīĭį',
      'j': 'ĵ',
      'k': 'ķ',
      'l': 'ĺļľ',
      'n': 'ñńņň',
      'o': 'òóôõöōŏőǒ',
      'r': 'ŕŗř',
      's': 'śŝşšș',
      't': 'ţťț',
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
