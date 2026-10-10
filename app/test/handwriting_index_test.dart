import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/search/ink_text_boxes.dart';
import 'package:len/data/search/search_index.dart';
import 'package:len/data/search/search_query.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/search/editor/ink_match_rects.dart';
import 'package:len/ink/recognition/handwriting_indexer.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';
import 'package:len/ink/recognition/recognition_service.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'handwriting_clustering_test.dart' show twoLines;
import 'support/fake_recognizer.dart';
import 'sync_test.dart' show FakeServer, apiFor, device;

const words = {'alpha': 'alpha', 'beta': 'beta', 'gamma': 'gamma', 'delta': 'delta', 'eps': 'eps'};

void main() {
  late AppServices s;
  late FakeRecognizer fake;
  late HandwritingIndexer indexer;
  late String page;
  late String notebook;

  HandwritingIndexer indexerFor(AppServices services, FakeRecognizer recognizer) =>
      HandwritingIndexer(
        services.database,
        recognizer: recognizer,
        language: () => 'en-US',
        idleDelay: Duration.zero,
        pauseBetweenLines: Duration.zero,
      );

  setUp(() {
    s = AppServices.create(AppDatabase.inMemory());
    fake = FakeRecognizer(words: {...words});
    indexer = indexerFor(s, fake);
    final nb = s.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    notebook = nb.id;
    s.pages.addPage(nb.id);
    page = s.pages.pagesOf(nb.id).last.id;
  });
  tearDown(() {
    indexer.dispose();
    s.dispose();
  });

  List<SearchHit> find(String q) => s.search.index.search(SearchQuery(q), notebookId: notebook);
  List<String> lines() => [
    for (final r in s.database.db.select('SELECT text FROM ink_text ORDER BY y'))
      r['text'] as String,
  ];
  int queued() => indexer.pendingCount;

  test('strokes are queued by triggers; indexing recognises lines into search', () async {
    s.strokes.save(twoLines(page));
    expect(queued(), 1);
    indexer.start();
    await indexer.run();
    expect(queued(), 0);
    expect(lines(), ['alpha beta gamma', 'delta eps']);
    final hit = find('gam').single;
    expect(hit.kind, SearchHitKind.handwriting);
    expect(hit.surfaceId, page);
    expect(hit.pageIndex, 1);
    expect(hit.body, 'alpha beta gamma');

    final boxes = s.search.index.inkTextBoxes(hit.refId)!;
    expect(boxes.line.top, closeTo(99, 0.1));
    expect(boxes.words, hasLength(3));
    final gamma = InkMatchRects.of(hit.body, (start: 11, end: 14), boxes.line, boxes.words);
    expect(gamma.single.left, closeTo(269, 0.1), reason: 'the matched word only');
  });

  test('only changed lines are recognised again; erasing removes their text', () async {
    s.strokes.save(twoLines(page));
    indexer.start();
    await indexer.run();
    expect(fake.requests, hasLength(2));

    fake.words['later'] = 'omega';
    s.strokes.save([
      scribble('later', page, const Rect.fromLTRB(290, 180, 360, 210), createdAt: 9),
    ]);
    await indexer.run();
    expect(fake.requests, hasLength(3));
    expect(fake.requests.last, ['delta', 'eps', 'later']);
    expect(lines(), ['alpha beta gamma', 'delta eps omega']);

    s.strokes.delete(['delta', 'eps', 'later']);
    await indexer.run();
    expect(fake.requests, hasLength(3), reason: 'nothing left to recognise');
    expect(lines(), ['alpha beta gamma']);
    expect(find('omega'), isEmpty);
    expect(find('alpha'), hasLength(1));
  });

  test('edits and undo through a SurfaceModel re-index the surface', () async {
    final model = SurfaceModel(surfaceId: page, repository: s.strokes);
    addTearDown(model.dispose);
    model.commit(InkEdit(added: twoLines(page)));
    indexer.start();
    await indexer.run();
    expect(find('delta'), hasLength(1));

    model.undo();
    expect(queued(), 1);
    await indexer.run();
    expect(lines(), isEmpty);
    expect(find('delta'), isEmpty);

    model.redo();
    await indexer.run();
    expect(find('delta'), hasLength(1));
  });

  test('a commit wakes a started indexer (no explicit call)', () async {
    indexer.start();
    s.strokes.save(twoLines(page));
    for (var i = 0; i < 100 && lines().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(lines(), ['alpha beta gamma', 'delta eps']);
  });

  test('strokes applied by sync are indexed on the receiving device', () async {
    final server = FakeServer();
    final a = device(server), b = device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final nb = a.notebooks.create(
      title: 'Shared',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    a.strokes.save(twoLines(nb.id));
    await a.sync.engine.sync(apiFor(server));
    await b.sync.engine.sync(apiFor(server));

    final onB = indexerFor(b, FakeRecognizer(words: {...words}));
    addTearDown(onB.dispose);
    expect(onB.pendingCount, 1);
    onB.start();
    await onB.run();
    final hit = b.search.index.search(SearchQuery('eps')).single;
    expect(hit.notebookId, nb.id);
    expect(hit.pageIndex, isNull, reason: 'canvases have no pages');
  });

  test('a change during recognition keeps the surface queued', () async {
    final slow = _GatedRecognizer(words);
    final gated = indexerFor(s, slow)..start();
    addTearDown(gated.dispose);
    s.strokes.save(twoLines(page));
    final running = gated.run();
    await slow.started.future;
    s.strokes.delete(['eps']);
    slow.gate.complete();
    await running;
    expect(gated.pendingCount, 0, reason: 'the run picked the surface up again');
    final texts = [for (final r in s.database.db.select('SELECT text FROM ink_text')) r['text']];
    expect(texts, containsAll(['alpha beta gamma', 'delta']));
  });

  test('failures leave the queue for later', () async {
    fake.downloaded = false;
    s.strokes.save(twoLines(page));
    indexer.start();
    await indexer.run();
    expect(queued(), 1);
    expect(indexer.lastError, isNotNull);
  });

  test('word boxes are kept only when the words match the clusters', () {
    expect(InkTextBoxes.decode(InkTextBoxes.encode([const Rect.fromLTWH(1, 2, 3, 4)])), [
      const Rect.fromLTWH(1, 2, 3, 4),
    ]);
    expect(InkTextBoxes.decode('nonsense'), isNull);
    expect(InkTextBoxes.decode('[[1, 2]]'), isNull);
    const line = Rect.fromLTWH(0, 0, 100, 10);
    expect(InkMatchRects.of('a b', (start: 0, end: 1), line, null), [line]);
    expect(InkMatchRects.of('a b', (start: 0, end: 1), line, [line]), [line]);
  });

  group('RecognitionService', () {
    RecognitionService service(FakeRecognizer recognizer, {List<Locale> locales = const []}) {
      final r = RecognitionService(
        recognizer: recognizer,
        settings: SettingsRepository(s.database),
        database: s.database,
        deviceLocales: () => locales,
        idleDelay: Duration.zero,
      );
      addTearDown(r.dispose);
      return r;
    }

    test('language follows the device until chosen; a new language re-queues all', () async {
      final r = service(fake, locales: const [Locale('de', 'CH')]);
      expect(r.language, 'de-DE');
      expect(r.isAutomaticLanguage, isTrue);
      s.strokes.save(twoLines(page));
      await r.start();
      expect(r.indexer.isActive, isTrue);
      await r.indexer.run();
      expect(fake.languages.toSet(), {'de-DE'});

      await r.setLanguage('fr-FR');
      expect(r.language, 'fr-FR');
      expect(r.indexer.pendingCount, 1);
      await r.indexer.run();
      expect(fake.languages.last, 'fr-FR');
      expect(lines(), ['alpha beta gamma', 'delta eps']);
    });

    test('indexing off forgets recognised text; on recognises again', () async {
      final r = service(fake);
      s.strokes.save(twoLines(page));
      await r.start();
      await r.indexer.run();
      expect(find('beta'), hasLength(1));

      await r.setIndexingEnabled(false);
      expect(r.indexer.isActive, isFalse);
      expect(find('beta'), isEmpty);
      await r.setIndexingEnabled(true);
      expect(r.indexer.isActive, isTrue);
      await r.indexer.run();
      expect(find('beta'), hasLength(1));
    });

    test('a missing model is downloaded (Wi-Fi) before indexing; deleting pauses', () async {
      fake.downloaded = false;
      final r = service(fake);
      await r.start();
      await pumpEventQueue();
      expect(fake.downloads, 1);
      expect(r.modelStatus, ModelStatus.downloaded);
      expect(r.indexer.isActive, isTrue);

      await r.deleteModel();
      expect(r.modelStatus, ModelStatus.missing);
      expect(r.indexer.isActive, isFalse);
    });

    test('unsupported platforms never index', () async {
      final r = service(FakeRecognizer(supported: false));
      await r.start();
      expect(r.indexer.isActive, isFalse);
      expect(() => r.recognize(twoLines(page)), throwsUnsupportedError);
    });
  });
}

/// Holds the first recognition until [gate] completes.
class _GatedRecognizer extends FakeRecognizer {
  _GatedRecognizer(Map<String, String> words) : super(words: {...words});

  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<List<RecognitionCandidate>> recognize(
    strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await gate.future;
    }
    return super.recognize(strokes, language: language, writingArea: writingArea);
  }
}
