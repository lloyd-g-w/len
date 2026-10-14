import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';

import 'support/property.dart';

/// Pieces of text: words, accents, other scripts, and what FTS5 query
/// syntax would trip over. (Not decomposed accents or characters beyond
/// the BMP in indexed text: see [_unusual].)
const _pieces = [
  'a', 'b', 'Z', 'x', '1', '42', 'é', 'É', 'ü', 'ñ', 'ç', 'ø', 'ł', 'ß', 'İ', 'ı', 'Ж', 'й', //
  'ё', 'Ω', 'ά', '中文', 'ﬁ', 'ǅ', '٣', '_', '-', "'", '’', '"', '*', '(', ')', ':', '^', '+',
  '.', ',', '%', '\\', ' ', ' ', ' ', '\n', '\t', '\u00A0', 'AND', 'OR', 'NOT', 'NEAR', '{', '}',
];

/// Text the Dart matcher reads differently from the index (a tolerance):
/// a decomposed accent in indexed text (the index drops it, the matcher
/// keeps it to keep offsets), and emoji, at which the index splits words
/// but which the matcher counts as letters (as all characters beyond the
/// BMP). Only parsing is checked with them.
const _unusual = ['e\u0301', '😀', '𝐀'];

String _text(math.Random r, int pieces, [List<String> extra = const []]) {
  final all = [..._pieces, ...extra];
  return [for (var i = r.nextInt(pieces + 1); i > 0; i--) all[r.nextInt(all.length)]].join();
}

/// A query: random text, or a word of [text] (whole or a prefix), with
/// case changed now and then.
String _query(math.Random r, String text) {
  final words = [for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(text)) m[0]!];
  if (words.isEmpty || r.nextInt(3) == 0) return _text(r, 4);
  final word = words[r.nextInt(words.length)];
  final prefix = word.substring(0, 1 + r.nextInt(word.length));
  // Typed decomposed now and then (the index folds it the same).
  final typed = r.nextInt(4) == 0 ? prefix.replaceAll('é', 'e\u0301') : prefix;
  return r.nextBool() ? typed.toUpperCase() : typed;
}

void main() {
  late AppServices s;
  late Notebook nb;
  late SearchIndex index;
  setUpAll(() {
    s = AppServices.create(AppDatabase.inMemory());
    index = SearchIndex(s.database);
    nb = s.notebooks.create(
      title: 'x',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
  });
  tearDownAll(() => s.dispose());

  bool found(SearchIndex index, String query) =>
      index.search(SearchQuery(query)).any((h) => h.refId == nb.id);

  test('parsing any text gives folded word terms', () async {
    await forAll(
      (r) => _text(r, 12, _unusual),
      (input) {
        final q = SearchQuery(input);
        for (final t in q.terms) {
          expect(t, isNotEmpty);
          expect(t, SearchText.fold(t), reason: 'folded');
          for (final c in t.codeUnits) {
            expect(SearchText.isWordChar(c), isTrue, reason: '"$t" is a word');
          }
        }
        expect(q.terms.toSet(), hasLength(q.terms.length));
        expect(SearchText.fold(input), hasLength(input.length), reason: 'offsets kept');
        for (final range in q.ranges(input)) {
          expect(range.start, lessThan(range.end));
          expect(range.end, lessThanOrEqualTo(input.length));
        }
      },
      runs: 2000,
      seed: 1,
    );
  });

  test('FTS5 accepts every query and finds what the Dart matcher finds', () async {
    expect(index.usesFts, isTrue);
    await forAll(
      (r) {
        final text = _text(r, 12);
        return (text, _query(r, text));
      },
      (c) {
        final (text, query) = c;
        s.notebooks.update(s.notebooks.get(nb.id)!.copyWith(title: text));
        final q = SearchQuery(query);
        if (q.isEmpty) return expect(index.search(q), isEmpty);
        expect(found(index, query), q.matches(text), reason: 'FTS "${q.ftsExpression}"');
      },
      runs: 1500,
      seed: 2,
      describe: (c) => 'text ${c.$1.runes.toList()} "${c.$1}", query "${c.$2}"',
    );
  });

  test('every word of an indexed text finds it', () async {
    await forAll(
      (r) => _text(r, 12),
      (text) {
        s.notebooks.update(s.notebooks.get(nb.id)!.copyWith(title: text));
        for (final term in SearchQuery(text).terms) {
          expect(found(index, term), isTrue, reason: 'word "$term"');
        }
      },
      runs: 300,
      seed: 3,
      describe: (text) => '"$text" ${text.runes.toList()}',
    );
  });

  test('without FTS5, LIKE finds plain lowercase words the same way', () async {
    final like = SearchIndex(s.database, preferFts: false);
    const ascii = ['ab', 'b', 'ca', 'a1', '_', '%', '\\', ' ', ' ', '-', '"', "'"];
    await forAll(
      (r) {
        String text(int n) => [for (var i = n; i > 0; i--) ascii[r.nextInt(ascii.length)]].join();
        return (text(1 + r.nextInt(10)), text(1 + r.nextInt(3)));
      },
      (c) {
        final (text, query) = c;
        s.notebooks.update(s.notebooks.get(nb.id)!.copyWith(title: text));
        final q = SearchQuery(query);
        expect(found(like, query), q.matches(text));
        if (!q.isEmpty) expect(found(index, query), q.matches(text), reason: 'FTS agrees');
      },
      runs: 500,
      seed: 4,
    );
  });
}
