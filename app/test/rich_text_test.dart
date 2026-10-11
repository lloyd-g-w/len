import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/font_licenses.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/rich_text_buffer.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/features/editor/tools/text/rich_text_controller.dart';
import 'package:len/ink/elements/text_hit_test.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock;

/// Types [text] at the caret, as the text field would.
void type(RichTextController c, String text) {
  final v = c.value;
  final s = v.selection;
  c.value = TextEditingValue(
    text: v.text.replaceRange(s.start, s.end, text),
    selection: TextSelection.collapsed(offset: s.start + text.length),
  );
}

/// Deletes the character before the caret (or the selection).
void backspace(RichTextController c) {
  final v = c.value;
  final s = v.selection;
  final start = s.isCollapsed ? s.start - 1 : s.start;
  c.value = TextEditingValue(
    text: v.text.replaceRange(start, s.end, ''),
    selection: TextSelection.collapsed(offset: start),
  );
}

void select(RichTextController c, int start, int end) => c.selection = TextSelection(
  baseOffset: MarkerOffsets(c.data).toDisplay(start),
  extentOffset: MarkerOffsets(c.data).toDisplay(end),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled font has its faces and its OFL licence', () async {
    for (final font in TextFont.values) {
      for (final bold in [false, true]) {
        for (final italic in [false, true]) {
          final bytes = await rootBundle.load(font.asset(bold: bold, italic: italic));
          expect(bytes.lengthInBytes, greaterThan(10000));
        }
      }
      expect(await rootBundle.loadString(font.licenseAsset), contains('SIL OPEN FONT LICENSE'));
    }
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    expect(entries.expand((e) => e.packages), containsAll(['Inter font', 'Caveat font']));
  });

  group('TextData', () {
    test('plain boxes stay compact; rich data round-trips through JSON', () {
      final plain = const TextData(text: 'Hi').toJson();
      expect(plain['spans'], isEmpty);
      expect(plain['paras'], isEmpty);

      final rich = TextData.rich(
        text: 'Title\nitem one\nitem two',
        spans: const [
          StyledRange(0, 5, SpanStyle(bold: true, color: 0xFFC2255C)),
          StyledRange(11, 14, SpanStyle(highlight: 0x80FFEB3B, size: 30, font: TextFont.mono)),
        ],
        paras: const [
          ParaStyle(heading: 1),
          ParaStyle(list: ListKind.check, checked: true),
          ParaStyle(list: ListKind.number, indent: 1),
        ],
        font: TextFont.lora,
        fontSize: 20,
        align: TextAlignment.center,
        autoWidth: true,
      );
      final json = jsonDecode(jsonEncode(rich.toJson())) as Map<String, Object?>;
      expect(json['spans'], [
        [
          0,
          5,
          {'b': true, 'c': 0xFFC2255C},
        ],
        [
          11,
          14,
          {'hl': 0x80FFEB3B, 'sz': 30.0, 'f': 'mono'},
        ],
      ]);
      expect(json['paras'], [
        {'h': 1},
        {'l': 'check', 'x': true},
        {'l': 'number', 'n': 1},
      ]);
      expect(TextData.fromJson(json), rich);
      expect(TextData.fromJson(json).isRich, isTrue);
    });

    test('spans are normalised: clipped, merged, plain ones dropped', () {
      final d = TextData.rich(
        text: 'abcdef',
        spans: const [
          StyledRange(0, 2, SpanStyle(bold: true)),
          StyledRange(2, 4, SpanStyle(bold: true)),
          StyledRange(4, 5, SpanStyle()),
          StyledRange(5, 99, SpanStyle(italic: true)),
        ],
      );
      expect(d.spans, const [
        StyledRange(0, 4, SpanStyle(bold: true)),
        StyledRange(5, 6, SpanStyle(italic: true)),
      ]);
    });

    test('malformed formatting is ignored, unknown keys survive edits', () {
      final d = TextData.fromJson({
        'text': 'x',
        'spans': [
          'junk',
          [0, 1, 'no'],
          [
            0,
            1,
            {'b': true, 'f': 'comic'},
          ],
        ],
        'paras': [42],
        'font': 'nope',
        'size': 'big',
      });
      expect(d.spans, const [StyledRange(0, 1, SpanStyle(bold: true))]);
      expect(d.font, TextFont.inter);
      expect(d.fontSize, 24);
      expect(d.toJson({'future': 1})['future'], 1);
    });

    test('scaling a box scales span sizes too', () {
      final d = TextData.rich(
        text: 'ab',
        spans: const [StyledRange(1, 2, SpanStyle(size: 40))],
        fontSize: 20,
      ).withFontSize(30);
      expect(d.fontSize, 30);
      expect(d.spans.single.style.size, 60);
    });
  });

  group('RichTextBuffer', () {
    test('Enter continues a list unchecked, without the heading', () {
      final b = RichTextBuffer(
        TextData.rich(
          text: 'todo',
          paras: const [ParaStyle(heading: 2, list: ListKind.check, checked: true, indent: 1)],
        ),
      )..replace(4, 4, '\n', SpanStyle.plain);
      expect(b.paras, const [
        ParaStyle(heading: 2, list: ListKind.check, checked: true, indent: 1),
        ParaStyle(list: ListKind.check, indent: 1),
      ]);
    });

    test('joining lines keeps the first line\'s style', () {
      final b = RichTextBuffer(
        TextData.rich(text: 'a\nb', paras: const [ParaStyle(heading: 1), ParaStyle.body]),
      )..replace(1, 2, '', SpanStyle.plain);
      expect(b.text, 'ab');
      expect(b.paras, const [ParaStyle(heading: 1)]);
    });

    test('numbers count consecutive items per indent level', () {
      const n = ParaStyle(list: ListKind.number);
      const sub = ParaStyle(list: ListKind.number, indent: 1);
      final paras = [n, sub, sub, n, ParaStyle.body, n];
      expect(
        // A body line restarts the count.
        [
          for (final i in [0, 1, 2, 3, 5]) RichTextBuffer.listNumberOf(paras, i),
        ],
        [1, 1, 2, 2, 1],
      );
    });
  });

  group('MarkerOffsets', () {
    test('maps around one placeholder per list line', () {
      final d = TextData.rich(
        text: 'ab\ncd\nef',
        paras: const [
          ParaStyle.body,
          ParaStyle(list: ListKind.bullet),
          ParaStyle.body,
        ],
      );
      final m = MarkerOffsets(d);
      expect(m.display(d.text), 'ab\n\uFFFCcd\nef');
      expect(m.toDisplay(3), 4); // the caret at the line start sits after the marker
      expect(m.toDisplay(2), 2);
      expect(m.toModel(3), 3);
      expect(m.toModel(4), 3);
      expect(m.toModel(9), 8);
      expect(m.isBeforeMarker(3), isTrue);
    });
  });

  group('RichTextController', () {
    test('formats a selection, or what is typed next', () {
      final c = RichTextController(const TextData());
      type(c, 'Hello');
      select(c, 0, 5);
      c.toggleBold();
      expect(c.data.spans, const [StyledRange(0, 5, SpanStyle(bold: true))]);
      c.selection = const TextSelection.collapsed(offset: 5);
      c.toggleBold(); // off for what follows
      c.toggleItalic();
      type(c, ' you');
      expect(c.data.spans, const [
        StyledRange(0, 5, SpanStyle(bold: true)),
        StyledRange(5, 9, SpanStyle(italic: true)),
      ]);
      select(c, 0, 9);
      expect(c.selectionHas((s) => s.bold), isFalse);
      c.setColor(0xFF0CA678);
      c.setFont(TextFont.caveat);
      c.setSize(40);
      expect(c.data.spans.every((s) => s.style.color == 0xFF0CA678), isTrue);
      expect(c.data.spans.every((s) => s.style.font == TextFont.caveat), isTrue);
      expect(c.currentSize, 40);
    });

    test('in an empty box, font, size and colour set the box defaults', () {
      final c = RichTextController(const TextData())
        ..setFont(TextFont.lora)
        ..setSize(32)
        ..setColor(0xFF112233);
      expect(c.box.font, TextFont.lora);
      expect(c.box.fontSize, 32);
      expect(c.box.color, 0xFF112233);
      type(c, 'x');
      expect(c.data.spans, isEmpty);
    });

    test('lists: Enter continues, Enter on an empty item ends, backspace removes the bullet', () {
      final c = RichTextController(const TextData());
      type(c, 'one');
      c.toggleList(ListKind.bullet);
      expect(c.text, '\uFFFCone');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
      type(c, '\n');
      type(c, 'two');
      expect(c.data.text, 'one\ntwo');
      expect(c.data.paras.map((p) => p.list), [ListKind.bullet, ListKind.bullet]);
      type(c, '\n');
      expect(c.data.paras.last.list, ListKind.bullet);
      type(c, '\n'); // empty item: ends the list instead
      expect(c.data.text, 'one\ntwo\n');
      expect(c.data.paras.last.list, ListKind.none);

      // Backspace right after a marker removes the marker, not text.
      c.selection = TextSelection.collapsed(offset: MarkerOffsets(c.data).toDisplay(4));
      backspace(c);
      expect(c.data.text, 'one\ntwo\n');
      expect(c.data.paras.map((p) => p.list), [ListKind.bullet, ListKind.none, ListKind.none]);
    });

    test('the caret steps over markers', () {
      final c = RichTextController(
        TextData.rich(
          text: 'ab\ncd',
          paras: const [
            ParaStyle.body,
            ParaStyle(list: ListKind.number),
          ],
        ),
      );
      // Display: "ab\n￼cd". Moving left from after the marker lands at
      // the end of the previous line, not between the break and marker.
      c.selection = const TextSelection.collapsed(offset: 4);
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.selection.baseOffset, 2);
      // A tap before the marker puts the caret after it.
      c.selection = const TextSelection.collapsed(offset: 0);
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.selection.baseOffset, 4);
    });

    test('indent, headings and checklist toggles act on whole lines', () {
      final c = RichTextController(const TextData(text: 'a\nb'));
      select(c, 0, 3);
      c.toggleList(ListKind.check);
      expect(c.indent(1), isTrue);
      expect(c.data.paras.every((p) => p.indent == 1), isTrue);
      c.toggleChecked(1);
      expect(c.data.paras[1].checked, isTrue);
      c.toggleHeading(1);
      expect(c.data.paras.every((p) => p.heading == 1), isTrue);
      c.toggleHeading(1);
      expect(c.data.paras.every((p) => p.heading == 0), isTrue);
      c.toggleList(ListKind.check);
      expect(c.data.isRich, isFalse);
      expect(c.indent(1), isFalse);
    });

    test('copy puts plain text on the clipboard; pasting it keeps formatting', () async {
      String? clip;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (_) async => null),
      );
      final c = RichTextController(
        TextData.rich(
          text: 'bold\nx',
          spans: const [StyledRange(0, 4, SpanStyle(bold: true))],
          paras: const [
            ParaStyle(list: ListKind.bullet),
            ParaStyle(list: ListKind.bullet),
          ],
        ),
      );
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      await c.copySelection();
      expect(clip, 'bold\nx');

      final other = RichTextController(const TextData());
      type(other, 'bold\nx');
      expect(other.data.spans, const [StyledRange(0, 4, SpanStyle(bold: true))]);

      select(c, 0, 4);
      await c.copySelection(cut: true);
      expect(c.data.text, '\nx');
    });
  });

  group('layout', () {
    test('headings are taller, list markers get placeholders', () {
      final body = TextLayout.heightOf(const TextData(text: 'x'), 300);
      final heading = TextLayout.heightOf(
        TextData.rich(text: 'x', paras: const [ParaStyle(heading: 1)]),
        300,
      );
      expect(heading, closeTo(body * 1.6, 1));
      final list = TextLayout.layout(
        TextData.rich(
          text: 'a\nb',
          paras: const [
            ParaStyle(list: ListKind.bullet),
            ParaStyle(list: ListKind.check),
          ],
        ),
        300,
      );
      expect(list.markerBoxes, hasLength(2));
      expect(list.markerBoxes.first.left, 0);
      expect(list.markerBoxes.first.width, closeTo(24 * 1.6, 1e-3));
      list.dispose();
    });

    test('auto width fits the longest line', () {
      final short = TextLayout.naturalWidth(const TextData(text: 'ab'));
      final long = TextLayout.naturalWidth(const TextData(text: 'ab\nabcdefgh'));
      expect(long, greaterThan(short * 2));
      final h = TextLayout.heightOf(const TextData(text: 'ab\nabcdefgh'), long);
      expect(h, closeTo(2 * 24 * TextLayout.lineHeight, 1));
    });

    test('tapping a committed checkbox ticks it as one undoable edit', () {
      final db = AppDatabase.inMemory();
      final clock = FakeClock();
      final model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      );
      addTearDown(() {
        model.dispose();
        db.close();
      });
      final data = TextData.rich(
        text: 'milk\neggs',
        paras: const [
          ParaStyle(list: ListKind.check),
          ParaStyle(list: ListKind.check),
        ],
      );
      final e = SurfaceElement(
        id: 't',
        surfaceId: 's',
        type: 'text',
        rect: Rect.fromLTWH(100, 100, 300, TextLayout.heightOf(data, 300)),
        z: 1,
        createdAt: 1,
        data: data.toJson(),
      );
      model.commit(InkEdit(addedElements: [e]));
      final layout = TextLayout.layout(data, 300);
      final box = layout.markers[1].checkbox(layout.markerBoxes[1]);
      layout.dispose();
      final at = e.rect.topLeft + box.center;
      expect(TextHitTest.checkboxAt(e, at), 1);
      expect(TextHitTest.checkboxAt(e, e.rect.topLeft + const Offset(200, 5)), isNull);
      TextHitTest.toggleChecked(model, e, 1);
      final ticked = TextData.fromJson(model.elementById('t')!.data);
      expect(ticked.paras.map((p) => p.checked), [false, true]);
      model.undo();
      expect(TextData.fromJson(model.elementById('t')!.data).paras[1].checked, isFalse);
    });
  });
}
