import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/text_flow_chains.dart';

SurfaceElement box(String id, String page, String text, {TextFlow? flow}) => SurfaceElement(
  id: id,
  surfaceId: page,
  type: ElementType.text.name,
  rect: const Rect.fromLTWH(40, 60, 300, 90),
  z: 1,
  createdAt: 1,
  data: TextData.rich(text: text).withFlow(flow).toJson(),
);

void main() {
  late AppServices services;
  late Notebook nb;
  late List<String> pages;

  setUp(() {
    services = AppServices.create(AppDatabase.inMemory());
    nb = services.notebooks.create(
      title: 'Flow',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    services.pages
      ..addPage(nb.id)
      ..addPage(nb.id);
    pages = [for (final p in services.pages.pagesOf(nb.id)) p.id];
    services.elements.save([
      box('head', pages[0], 'one two'),
      box(
        'next',
        pages[1],
        'three',
        flow: const TextFlow(from: 'head', joined: true, direction: TextDirection.rtl),
      ),
    ]);
  });

  tearDown(() => services.dispose());

  test('sync carries a continuation\'s flow; a malformed one is skipped', () {
    final records = services.elements.dirtyRecords(10);
    final next = records.firstWhere((r) => r.id == 'next');
    final wire = jsonDecode(jsonEncode(next.data)) as Map<String, Object?>;
    expect((wire['data']! as Map)['flow'], {
      'from': 'head',
      'joined': true,
      'numbers': <int>[],
      'dir': 'rtl',
    });

    final other = AppServices.create(AppDatabase.inMemory());
    addTearDown(other.dispose);
    final repo = ElementRepository(other.database, deviceId: 'b');
    repo.writeRemote(
      SyncRecord(
        collection: 'elements',
        id: next.id,
        updatedAt: next.updatedAt,
        deviceId: 'a',
        deleted: false,
        data: wire,
      ),
    );
    final stored = repo.allOn(pages[1]).single;
    expect(
      TextFlowChains.flowOf(stored),
      const TextFlow(from: 'head', joined: true, direction: TextDirection.rtl),
    );

    final bad = <String, Object?>{
      ...wire,
      'data': <String, Object?>{
        ...(wire['data']! as Map<String, Object?>),
        'flow': {'from': 'head'},
      },
    };
    // Malformed: the record is skipped (the box stays as it was).
    expect(
      () => repo.writeRemote(
        SyncRecord(
          collection: 'elements',
          id: next.id,
          updatedAt: next.updatedAt + 1,
          deviceId: 'a',
          deleted: false,
          data: bad,
        ),
      ),
      throwsFormatException,
    );
    expect(TextFlowChains.flowOf(repo.allOn(pages[1]).single), isNotNull);
  });

  test('a duplicated notebook keeps its chains, linked to the copies', () {
    final copy = services.notebooks.duplicate(nb.id)!;
    final copied = [for (final p in services.pages.pagesOf(copy.id)) p.id];
    final head = services.elements.allOn(copied[0]).single;
    final next = services.elements.allOn(copied[1]).single;
    expect(head.id, isNot('head'));
    expect(TextFlowChains.flowOf(next)!.from, head.id);
    expect(TextFlowChains.flowOf(next)!.joined, isTrue);
  });

  test('a continuation copied without its box before stands alone', () {
    final other = services.notebooks.create(
      title: 'Other',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final copied = services.notebooks.copyPages(nb.id, [pages[1]], other.id);
    final next = services.elements.allOn(copied.copies[pages[1]]!).single;
    expect(TextFlowChains.flowOf(next), isNull);
    expect(TextData.fromJson(next.data).text, 'three');
  });
}
