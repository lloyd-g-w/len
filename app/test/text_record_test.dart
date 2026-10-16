import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/schema_migrations.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/paragraph_direction.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/text/text_record.dart';

import 'data_test.dart' show FakeClock;

void main() {
  group('ParagraphDirection', () {
    test('the first strong character decides (P2 / P3)', () {
      expect(ParagraphDirection.firstStrong('hello'), TextDirection.ltr);
      expect(ParagraphDirection.firstStrong('שלום'), TextDirection.rtl);
      expect(ParagraphDirection.firstStrong('مرحبا'), TextDirection.rtl);
      // Digits, punctuation and spaces are neutral.
      expect(ParagraphDirection.firstStrong('12, (!) שלום world'), TextDirection.rtl);
      expect(ParagraphDirection.firstStrong('3. Hello עולם'), TextDirection.ltr);
      expect(ParagraphDirection.firstStrong('٣٤ ٥'), isNull); // Arabic-Indic digits
      expect(ParagraphDirection.firstStrong('  '), isNull);
      // Other scripts are left-to-right; marks are not strong.
      expect(ParagraphDirection.firstStrong('Привет'), TextDirection.ltr);
      expect(ParagraphDirection.firstStrong('日本'), TextDirection.ltr);
      expect(ParagraphDirection.firstStrong('\u0301\u05D0'), TextDirection.rtl);
      // Explicit marks are strong; isolated text is skipped.
      expect(ParagraphDirection.firstStrong('\u200F1'), TextDirection.rtl);
      expect(ParagraphDirection.firstStrong('\u2067abc\u2069 שלום'), TextDirection.rtl);
      // Surrogate pairs (Adlam is right-to-left).
      expect(ParagraphDirection.firstStrong('1 \u{1E900}'), TextDirection.rtl);
      expect(ParagraphDirection.firstStrong('1 \u{1D400}'), TextDirection.ltr);
    });

    test('each paragraph has its own direction; neutral ones follow the one before', () {
      const rtl = TextDirection.rtl, ltr = TextDirection.ltr;
      expect(ParagraphDirection.of('Hello\nשלום\n\n123\nWorld'), [ltr, rtl, rtl, rtl, ltr]);
      // Leading neutral paragraphs take the first direction found.
      expect(ParagraphDirection.of('\n42\nمرحبا\nhi'), [rtl, rtl, rtl, ltr]);
      expect(ParagraphDirection.of(''), [ltr]);
      expect(ParagraphDirection.of('1\n2'), [ltr, ltr]);
      expect(ParagraphDirection.baseOf('12\nשלום\nhi'), rtl);
    });
  });

  group('TextRecord', () {
    final complete = TextData.rich(
      text: 'Todo\nmilk',
      spans: const [StyledRange(0, 4, SpanStyle(bold: true, size: 30, font: TextFont.lora))],
      paras: const [
        ParaStyle(heading: 1),
        ParaStyle(list: ListKind.check, checked: true, indent: 2),
      ],
      align: TextAlignment.end,
      autoWidth: true,
    );

    Map<String, Object?> json(TextData d) =>
        jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>;

    test('reads what TextData writes', () {
      expect(TextRecord.parse(json(complete)), complete);
      expect(TextRecord.parse(json(const TextData())), const TextData());
      expect(json(complete)['align'], 'end');
    });

    test('every field is required and checked; unknown keys are ignored', () {
      final good = json(complete);
      expect(TextRecord.parse({...good, 'future': 1}), complete);
      for (final key in good.keys) {
        expect(() => TextRecord.parse({...good}..remove(key)), throwsFormatException, reason: key);
      }
      final bad = <String, Object?>{
        'text': 3,
        'align': 'left', // the old format
        'font': 'comic',
        'size': 2,
        'color': -1,
        'autoWidth': 'yes',
        'spans': [
          [
            0,
            99,
            {'b': true},
          ],
        ],
        'paras': [
          {'h': 3},
        ],
      };
      for (final MapEntry(:key, :value) in bad.entries) {
        expect(() => TextRecord.parse({...good, key: value}), throwsFormatException, reason: key);
      }
      for (final span in [
        [0, 1, <String, Object?>{}], // unformatted
        [
          1,
          1,
          {'b': true},
        ], // empty
        [
          0,
          2,
          {'b': false},
        ],
        [
          0,
          2,
          {'c': 'red'},
        ],
        [
          0,
          2,
          {'f': 'comic'},
        ],
        'junk',
      ]) {
        expect(
          () => TextRecord.parse({
            ...good,
            'spans': [span],
          }),
          throwsFormatException,
          reason: '$span',
        );
      }
      expect(
        () => TextRecord.parse({
          ...good,
          'spans': [
            [
              0,
              3,
              {'b': true},
            ],
            [
              2,
              4,
              {'i': true},
            ],
          ],
        }),
        throwsFormatException,
        reason: 'overlapping spans',
      );
      for (final para in [
        {'l': 'star'},
        {'x': true},
        {'n': 1},
        {'l': 'bullet', 'n': 9},
        {'l': 'bullet', 'x': true},
      ]) {
        expect(
          () => TextRecord.parse({
            ...good,
            'paras': [para, <String, Object?>{}],
          }),
          throwsFormatException,
          reason: '$para',
        );
      }
      expect(
        () => TextRecord.parse({
          ...good,
          'paras': [<String, Object?>{}],
        }),
        throwsFormatException,
        reason: 'one entry per line',
      );
    });

    test('a continuation\'s flow is read strictly; it is the one optional key', () {
      const flow = TextFlow(from: 'head', joined: true, numbers: [2], direction: TextDirection.rtl);
      final continued = complete.withFlow(flow);
      final good = json(continued);
      expect(good['flow'], {
        'from': 'head',
        'joined': true,
        'numbers': [2],
        'dir': 'rtl',
      });
      expect(TextRecord.parse(good), continued);
      expect(TextRecord.parse(good).flow, flow);
      // Without one the box stands on its own (the first of a chain).
      expect(TextRecord.parse({...good}..remove('flow')).flow, isNull);
      final whole = good['flow']! as Map<String, Object?>;
      for (final key in whole.keys) {
        expect(
          () => TextRecord.parse({
            ...good,
            'flow': {...whole}..remove(key),
          }),
          throwsFormatException,
          reason: 'flow without $key',
        );
      }
      for (final bad in <Object?>[
        null,
        'head',
        {...whole, 'from': ''},
        {...whole, 'joined': 1},
        {
          ...whole,
          'numbers': [-1],
        },
        {...whole, 'dir': 'up'},
      ]) {
        expect(
          () => TextRecord.parse({...good, 'flow': bad}),
          throwsFormatException,
          reason: '$bad',
        );
      }
      // Through sync: a malformed flow skips the element record.
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final elements = ElementRepository(db, deviceId: 'a', clock: FakeClock());
      SyncRecord record(String id, Map<String, Object?> data) => SyncRecord(
        collection: 'elements',
        id: id,
        updatedAt: 5,
        deviceId: 'b',
        deleted: false,
        data: {
          'surfaceId': 's',
          'type': 'text',
          'x': 0,
          'y': 0,
          'w': 50,
          'h': 20,
          'rotation': 0,
          'z': 1,
          'createdAt': 1,
          'data': data,
        },
      );
      elements.applyRemote(record('ok', good));
      expect(TextData.fromJson(elements.allOn('s').single.data).flow, flow);
      expect(
        () => elements.applyRemote(
          record('bad', {
            ...good,
            'flow': {...whole}..remove('dir'),
          }),
        ),
        throwsFormatException,
      );
      expect(elements.allOn('s'), hasLength(1));
    });

    test('sync skips text elements in the old format', () {
      final db = AppDatabase.inMemory();
      final elements = ElementRepository(db, deviceId: 'a', clock: FakeClock());
      final element = SurfaceElement(
        id: 'e',
        surfaceId: 's',
        type: 'text',
        rect: const Rect.fromLTWH(0, 0, 50, 20),
        z: 1,
        createdAt: 1,
        data: {...complete.toJson(), 'align': 'right'},
      );
      elements.save([element]);
      final mine = elements.dirtyRecords(1).single;
      final record = SyncRecord(
        collection: mine.collection,
        id: 'other',
        updatedAt: mine.updatedAt + 1,
        deviceId: 'b',
        deleted: false,
        data: mine.data,
      );
      expect(() => elements.applyRemote(record), throwsFormatException);
      db.close();
    });
  });

  test('migration 14 stores alignments as start / end and sends them again', () {
    final db = AppDatabase.inMemory();
    final elements = ElementRepository(db, deviceId: 'a', clock: FakeClock());
    SurfaceElement box(String id, String align) => SurfaceElement(
      id: id,
      surfaceId: 's',
      type: 'text',
      rect: const Rect.fromLTWH(0, 0, 50, 20),
      z: 1,
      createdAt: 1,
      data: {
        ...const TextData(text: 'x').toJson(),
        'align': align,
      },
    );
    elements.save([box('l', 'left'), box('c', 'center'), box('r', 'right')]);
    db.db.execute('UPDATE elements SET dirty = 0');
    final before = {
      for (final r in db.db.select('SELECT id, updated_at FROM elements')) r['id']: r['updated_at'],
    };
    SchemaMigrations.all[13](db.db);
    final rows = {
      for (final r in db.db.select('SELECT id, data, updated_at, dirty FROM elements')) r['id']: r,
    };
    String align(String id) => (jsonDecode(rows[id]!['data'] as String) as Map)['align'] as String;
    expect([align('l'), align('c'), align('r')], ['start', 'center', 'end']);
    expect(rows['l']!['dirty'], 1);
    expect(rows['l']!['updated_at'], (before['l']! as int) + 1);
    expect(rows['c']!['dirty'], 0);
    expect(TextData.fromJson(elements.loadChunks('s', [(x: 0, y: 0)]).first.data).text, 'x');
    db.close();
  });
}
