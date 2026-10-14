import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/recognition/ink_clustering.dart';
import 'package:len/ink/recognition/recognition_languages.dart';
import 'package:len/ink/shapes/shape_builder.dart';

import 'support/fake_recognizer.dart';

/// Two lines of words, written in reading order.
List<Stroke> twoLines(String surface) => [
  scribble('alpha', surface, const Rect.fromLTRB(50, 100, 150, 130), createdAt: 1),
  scribble('beta', surface, const Rect.fromLTRB(175, 100, 245, 130), createdAt: 2),
  scribble('gamma', surface, const Rect.fromLTRB(270, 102, 380, 132), createdAt: 3),
  scribble('delta', surface, const Rect.fromLTRB(50, 180, 150, 210), createdAt: 4),
  scribble('eps', surface, const Rect.fromLTRB(175, 178, 260, 208), createdAt: 5),
];

List<List<String>> ids(List<InkLine> lines) => [
  for (final l in lines) [for (final s in l.strokes) s.id],
];

void main() {
  group('InkClustering', () {
    test('groups strokes into lines (top to bottom) and words (left to right)', () {
      final lines = InkClustering.lines(twoLines('p'));
      expect(ids(lines), [
        ['alpha', 'beta', 'gamma'],
        ['delta', 'eps'],
      ]);
      expect(lines.first.words.map((w) => w.strokes.single.id), ['alpha', 'beta', 'gamma']);
      expect(lines.first.bounds.top, closeTo(99, 1e-6));
      expect(lines.first.letterHeight, closeTo(32, 1e-6));
    });

    test('lines are found whatever order they were written in', () {
      // Written bottom right first.
      final strokes = twoLines('p').reversed.toList();
      final reordered = [
        for (var i = 0; i < strokes.length; i++)
          scribble(strokes[i].id, 'p', strokes[i].bounds.deflate(2), createdAt: i * 5000),
      ];
      expect(ids(InkClustering.lines(reordered)).map((l) => l.toSet()), [
        {'alpha', 'beta', 'gamma'},
        {'delta', 'eps'},
      ]);
    });

    test('dots and accents join their line and word, even when written later', () {
      final strokes = [
        ...twoLines('p'),
        scribble('dot', 'p', const Rect.fromLTRB(100, 86, 104, 90), createdAt: 9),
      ];
      final lines = InkClustering.lines(strokes);
      expect(lines, hasLength(2));
      expect(lines.first.strokes.map((s) => s.id), contains('dot'));
      expect(lines.first.words.first.strokes.map((s) => s.id).toSet(), {'alpha', 'dot'});
    });

    test('a column far to the right is a line of its own; highlights and shapes are ignored', () {
      final box = ShapeBuilder.dragged(
        ShapeKind.rectangle,
        const Offset(30, 90),
        const Offset(420, 150),
      );
      final strokes = [
        ...twoLines('p'),
        Stroke(
          id: 'box',
          surfaceId: 'p',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: ShapeBuilder.pointsOf(box),
          createdAt: 8,
          shape: box,
        ),
        scribble('far', 'p', const Rect.fromLTRB(700, 100, 780, 130), createdAt: 6),
        scribble(
          'marker',
          'p',
          const Rect.fromLTRB(40, 95, 400, 140),
          createdAt: 7,
          tool: InkTool.highlighter,
        ),
      ];
      final lines = InkClustering.lines(strokes);
      expect(ids(lines), [
        ['alpha', 'beta', 'gamma'],
        ['far'],
        ['delta', 'eps'],
      ]);
    });

    test('a word added later to the end of a line joins it', () {
      final strokes = [
        ...twoLines('p'),
        scribble('later', 'p', const Rect.fromLTRB(400, 101, 470, 131), createdAt: 100000),
      ];
      expect(ids(InkClustering.lines(strokes)).first, ['alpha', 'beta', 'gamma', 'later']);
    });

    test('keys identify the set of strokes', () {
      final a = twoLines('p');
      expect(InkClustering.keyOf(a), InkClustering.keyOf(a.reversed));
      expect(InkClustering.keyOf(a), isNot(InkClustering.keyOf(a.skip(1))));
      expect(InkClustering.lines(const []), isEmpty);
    });
  });

  group('RecognitionLanguages', () {
    test('picks the device locale, then its language, then English', () {
      expect(RecognitionLanguages.forLocales(const [Locale('de', 'AT')]), 'de-DE');
      expect(RecognitionLanguages.forLocales(const [Locale('en', 'GB')]), 'en-GB');
      expect(RecognitionLanguages.forLocales(const [Locale('pt', 'PT')]), 'pt-PT');
      expect(RecognitionLanguages.forLocales(const [Locale('xx'), Locale('fr')]), 'fr-FR');
      expect(RecognitionLanguages.forLocales(const [Locale('zh', 'CN')]), 'zh-Hani-CN');
      expect(RecognitionLanguages.forLocales(const []), 'en-US');
    });
  });
}
