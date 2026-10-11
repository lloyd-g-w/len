import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/sticker_codec.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/stickers/sticker.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/editor/tools/content_layer.dart';
import 'package:len/features/stickers/builtin_stickers.dart';
import 'package:len/features/stickers/sticker_panel.dart';
import 'package:len/ink/tool_settings.dart';

import 'document_editor_test.dart' show closeEditor, drawAt, inkOf, pumpEditor;
import 'support/two_devices.dart';

const _sha = 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd';

StickerContent _content() => StickerContent.normalized(
  [
    Stroke(
      id: 'x',
      surfaceId: 'p',
      tool: InkTool.highlighter,
      color: 0x80FFD43B,
      width: 12,
      points: const [StrokePoint(100, 200, 0.5), StrokePoint(160, 210, 0.75)],
      createdAt: 5,
    ),
  ],
  [
    SurfaceElement(
      id: 'i',
      surfaceId: 'p',
      type: 'image',
      rect: const Rect.fromLTWH(120, 180, 40, 30),
      rotation: 0.25,
      z: -2,
      createdAt: 1,
      data: const {'blob': _sha, 'width': 40, 'height': 30},
    ),
  ],
);

void main() {
  group('StickerContent', () {
    test('normalized content starts at the origin and round-trips through JSON', () {
      final c = _content();
      expect(c.bounds.topLeft.distance, lessThan(1e-9));
      final back = StickerCodec.decode(StickerCodec.encode(c));
      final p = back.strokes.single.points.first.offset;
      expect((p - c.strokes.single.points.first.offset).distance, lessThan(1e-3));
      expect(back.strokes.single.tool, InkTool.highlighter);
      expect(back.strokes.single.style, c.strokes.single.style);
      expect(back.elements.single.rect, c.elements.single.rect);
      expect(back.elements.single.rotation, 0.25);
      expect(back.elements.single.data['blob'], _sha);
    });

    test('malformed content is rejected', () {
      expect(() => StickerCodec.decode({'strokes': []}), throwsFormatException);
      expect(
        () => StickerCodec.decode({
          'strokes': [
            {'tool': 'pen', 'color': 1, 'width': 2, 'points': '!!'},
          ],
          'elements': [],
        }),
        throwsFormatException,
      );
      expect(
        () => StickerCodec.decode({
          'strokes': [],
          'elements': [
            {'type': 'text', 'x': 0, 'y': 0, 'w': 1, 'h': 1, 'rotation': 0, 'z': 0},
          ],
        }),
        throwsFormatException,
      );
    });

    test('built-in stickers are ink at the origin, in their categories', () {
      expect(BuiltinStickers.all, hasLength(greaterThanOrEqualTo(12)));
      for (final s in BuiltinStickers.all) {
        expect(s.builtIn, isTrue);
        expect(s.content.strokes, isNotEmpty, reason: s.name);
        expect(s.content.bounds.topLeft.distance, lessThan(1e-6), reason: s.name);
        expect(BuiltinStickers.categories, contains(s.category));
        expect(
          StickerCodec.decode(StickerCodec.encode(s.content)).strokes.length,
          s.content.strokes.length,
        );
      }
      expect(BuiltinStickers.all.map((s) => s.id).toSet(), hasLength(BuiltinStickers.all.length));
    });
  });

  group('StickerRepository', () {
    late AppServices s;
    setUp(() {
      s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
    });

    test('save, rename, move, delete, restore; images stay referenced', () {
      final sticker = s.stickers.create(name: 'Bee', category: ' ', content: _content());
      expect(sticker.category, 'My stickers');
      s.stickers.update(sticker.id, name: 'Wasp', category: 'Bugs');
      final stored = s.stickers.get(sticker.id)!;
      expect((stored.name, stored.category), ('Wasp', 'Bugs'));
      expect(s.sync.engine.blobReferences.all(), contains(_sha));
      s.stickers.delete(sticker.id);
      expect(s.stickers.list(), isEmpty);
      expect(s.sync.engine.blobReferences.all(), isNot(contains(_sha)));
      s.stickers.restore(sticker.id);
      expect(s.stickers.list(), hasLength(1));
    });

    test('malformed records are skipped', () {
      SyncRecord record(Map<String, Object?> data) => SyncRecord(
        collection: 'stickers',
        id: 'st',
        updatedAt: 5,
        deviceId: 'x',
        deleted: false,
        data: data,
      );
      final good = {
        'name': 'n',
        'category': 'c',
        'content': StickerCodec.encode(_content()),
        'createdAt': 1,
      };
      expect(
        () => s.stickers.applyRemote(
          record({
            ...good,
            'content': {'strokes': [], 'elements': []},
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => s.stickers.applyRemote(record({...good, 'category': ''})),
        throwsFormatException,
      );
      expect(s.stickers.applyRemote(record(good)), isTrue);
    });

    test('stickers round-trip between devices', () async {
      final (a, b) = twoDevices();
      final sticker = a.s.stickers.create(name: 'Bee', category: 'Bugs', content: _content());
      await a.sync();
      final changes = await b.sync();
      expect(changes.stickers, isTrue);
      final copy = b.s.stickers.get(sticker.id)!;
      expect(copy.name, 'Bee');
      expect(copy.content.elements.single.data['blob'], _sha);
      b.s.stickers.delete(sticker.id);
      await send(b, a);
      expect(a.s.stickers.list(), isEmpty);
    });
  });

  testWidgets('save a selection as a sticker, insert it by tap and by dragging', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    final page = s.pages.pagesOf(nb.id).first;
    await drawAt(tester, const Offset(400, 300));
    final layer = tester.widget<ContentLayer>(find.byType(ContentLayer));
    final selection = layer.content.selection;
    final mine = inkOf(s, page).last;
    selection.select([selection.model.strokeById(mine.id)!], const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save as sticker…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sticker-name-field')), 'Tick');
    await tester.enterText(find.byKey(const ValueKey('sticker-category-field')), 'Marks of mine');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = s.stickers.list().single;
    expect((saved.name, saved.category), ('Tick', 'Marks of mine'));
    expect(saved.content.strokes.single.points, hasLength(mine.points.length));

    // Open the panel from the menu: the saved sticker comes first.
    selection.clear();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();
    expect(find.byType(StickerPanel), findsOneWidget);
    await expectLater(find.byType(StickerPanel), matchesGoldenFile('goldens/sticker_panel.png'));

    final before = inkOf(s, page).length;
    await tester.tap(find.byKey(ValueKey('sticker-${saved.id}')));
    await tester.pumpAndSettle();
    expect(inkOf(s, page), hasLength(before + 1));
    expect(selection.strokes, hasLength(1));
    expect(layer.tools.tool, EditorTool.lasso);

    // Built-in stickers by category; drag the check mark onto the page.
    await tester.tap(find.byKey(const ValueKey('sticker-category-Marks')));
    await tester.pumpAndSettle();
    final check = BuiltinStickers.all.firstWhere((x) => x.name == 'Check mark');
    final from = tester.getCenter(find.byKey(ValueKey('sticker-${check.id}')));
    const to = Offset(500, 600);
    final drag = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(inkOf(s, page), hasLength(before + 1 + check.content.strokes.length));
    final placed = selection.strokes.first;
    final centre = selection.model.strokeById(placed.id)!.bounds.center;
    final screen = layer.viewport.toScreen(centre);
    expect((screen - to).distance, lessThan(60));

    await tester.tap(find.byTooltip('Close stickers'));
    await tester.pumpAndSettle();
    expect(find.byType(StickerPanel), findsNothing);
    await closeEditor(tester);
  });
}
