import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/recognised_text_repository.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/search/editor/ink_match_rects.dart';
import 'package:len/ink/recognition/handwriting_indexer.dart';
import 'package:len/sync/sync_api.dart';

import 'handwriting_clustering_test.dart' show twoLines;
import 'support/fake_recognizer.dart';
import 'support/fake_server.dart' show FakeServer, apiFor;

const words = {'alpha': 'alpha', 'beta': 'beta', 'gamma': 'gamma', 'delta': 'delta', 'eps': 'eps'};

/// A device on [server]: Android-like with a [recognizer] that works,
/// desktop-like with one that is unsupported.
class Device {
  Device(FakeServer server, this.recognizer)
    : services = AppServices.create(AppDatabase.inMemory(), recognizer: recognizer) {
    services.sync.configure(url: 'http://sync.test', token: FakeServer.token);
    indexer = HandwritingIndexer(
      services.database,
      recognizer: recognizer,
      shared: shared,
      language: () => language,
      languageChangedAt: () => services.settings.handwritingLanguageChangedAt,
      idleDelay: Duration.zero,
      pauseBetweenLines: Duration.zero,
    )..start();
    api = apiFor(server);
  }

  final AppServices services;
  final FakeRecognizer recognizer;
  late final HandwritingIndexer indexer;
  late final SyncApi api;
  String language = 'en-US';

  RecognisedTextRepository get shared => services.recognition.indexer.shared;

  Future<void> sync() => services.sync.engine.sync(api);
  Future<void> index() => indexer.run();

  List<SearchHit> find(String q) => services.search.index.search(SearchQuery(q));

  void dispose() {
    indexer.dispose();
    services.dispose();
  }
}

void main() {
  late FakeServer server;
  late Device phone, desktop;
  late String page;

  Future<Device> add(FakeRecognizer recognizer) async {
    final d = Device(server, recognizer);
    addTearDown(d.dispose);
    // The app's own indexer waits for quiet seconds; tests drive their own.
    await pumpEventQueue();
    d.services.recognition.indexer.stop();
    return d;
  }

  setUp(() async {
    server = FakeServer();
    phone = await add(FakeRecognizer(words: {...words}));
    desktop = await add(FakeRecognizer(supported: false));
    final nb = phone.services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    phone.services.pages.addPage(nb.id);
    page = phone.services.pages.pagesOf(nb.id).last.id;
    phone.services.strokes.save(twoLines(page));
    await phone.index();
    await phone.sync();
    await desktop.sync();
    await desktop.index();
  });

  test('a desktop finds handwriting recognised on a phone, with word highlights', () async {
    expect(phone.recognizer.requests, hasLength(2));
    final hit = desktop.find('gam').single;
    expect(hit.kind, SearchHitKind.handwriting);
    expect(hit.surfaceId, page);
    expect(hit.pageIndex, 1);
    expect(hit.body, 'alpha beta gamma');
    final boxes = desktop.services.search.index.inkTextBoxes(hit.refId)!;
    expect(boxes.words, hasLength(3), reason: 'boxes come from its own clustering');
    final gamma = InkMatchRects.of(hit.body, (start: 11, end: 14), boxes.line, boxes.words);
    expect(gamma.single.left, closeTo(269, 0.1));
    expect(desktop.find('eps'), hasLength(1));
    expect(desktop.shared.dirtyRecords(10), isEmpty, reason: 'desktops never write');
  });

  test('erasing on the desktop hides stale text at once, everywhere after sync', () async {
    desktop.services.strokes.delete(['eps']);
    await desktop.index();
    expect(desktop.find('eps'), isEmpty, reason: 'the line changed: its text is stale');
    expect(desktop.find('delta'), isEmpty, reason: 'not recognised yet');
    expect(desktop.find('alpha'), hasLength(1), reason: 'other lines keep their text');

    await desktop.sync();
    await phone.sync();
    await phone.index();
    expect(phone.recognizer.requests.last, ['delta'], reason: 'only the changed line');
    expect(phone.find('eps'), isEmpty);
    await phone.sync();
    await desktop.sync();
    await desktop.index();
    expect(desktop.find('delta'), hasLength(1));
    expect(desktop.find('eps'), isEmpty);
  });

  test('editing on the phone replaces the synced text; erasing all removes it', () async {
    phone.recognizer.words['later'] = 'omega';
    phone.services.strokes.save([
      scribble('later', page, const Rect.fromLTRB(290, 180, 360, 210), createdAt: 9),
    ]);
    await phone.index();
    await phone.sync();
    await desktop.sync();
    await desktop.index();
    expect(desktop.find('omega').single.body, 'delta eps omega');
    expect(desktop.find('alpha'), hasLength(1));

    phone.services.strokes.delete(['alpha', 'beta', 'gamma', 'delta', 'eps', 'later']);
    await phone.index();
    expect(phone.shared.read(page), isNull, reason: 'tombstoned');
    await phone.sync();
    await desktop.sync();
    await desktop.index();
    expect(desktop.find('alpha'), isEmpty);
    expect(desktop.find('omega'), isEmpty);
    expect(desktop.indexer.lineCount, 0);
  });

  test('another phone uses the synced text instead of recognising again', () async {
    final tablet = await add(FakeRecognizer(words: {...words}));
    await tablet.sync();
    await tablet.index();
    expect(tablet.recognizer.requests, isEmpty);
    expect(tablet.find('delta'), hasLength(1));
    expect(tablet.shared.dirtyRecords(10), isEmpty, reason: 'nothing new to sync');

    // Both phones recognise a new line concurrently: they converge.
    for (final d in [phone, tablet]) {
      d.recognizer.words['later'] = 'omega';
      d.services.strokes.save([
        scribble('later', page, const Rect.fromLTRB(290, 180, 360, 210), createdAt: 9),
      ]);
      await d.index();
    }
    await phone.sync();
    await tablet.sync();
    await phone.sync();
    await phone.index();
    await tablet.index();
    expect(phone.shared.dirtyRecords(10), isEmpty);
    expect(tablet.shared.dirtyRecords(10), isEmpty);
    expect(phone.shared.read(page)!.lines.values, ['alpha beta gamma', 'delta eps omega']);
  });

  test('a language chosen later replaces synced text in another language', () async {
    final tablet = await add(FakeRecognizer(words: {...words}));
    tablet.language = 'de-DE';
    await tablet.sync();
    await tablet.index();
    expect(tablet.recognizer.requests, hasLength(2), reason: 'synced text is in English');
    expect(tablet.shared.dirtyRecords(10), isEmpty, reason: 'the same lines: no takeover');

    await tablet.services.recognition.setLanguage('de-DE');
    tablet.services.recognition.indexer.stop();
    await tablet.index();
    expect(tablet.shared.read(page)!.language, 'de-DE');
    await tablet.sync();
    await phone.sync();
    await phone.index();
    expect(phone.shared.dirtyRecords(10), isEmpty, reason: 'the phone does not take it back');
  });

  test('malformed records are rejected', () {
    final repo = desktop.shared;
    SyncRecord record(Object? lines, {Object? language = 'en-US'}) => SyncRecord(
      collection: 'recognised_text',
      id: 'p',
      updatedAt: 1,
      deviceId: 'x',
      deleted: false,
      data: {'language': language, 'lines': lines},
    );
    for (final bad in [
      record('nope'),
      record([
        ['k'],
      ]),
      record([
        ['', 'text'],
      ]),
      record([
        ['k', 3],
      ]),
      record(<Object>[], language: ''),
      record(<Object>[], language: null),
    ]) {
      expect(() => repo.applyRemote(bad), throwsFormatException);
    }
    expect(repo.read('p'), isNull);
  });
}
