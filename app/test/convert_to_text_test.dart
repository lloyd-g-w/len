import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/text_data.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/recognition/convert_to_text.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show key, liveElements, liveStrokes, mouseDrag;
import 'data_test.dart' show FakeClock;
import 'support/fake_recognizer.dart';

/// "hello world" written in red at (100, 400), letters 40 high.
List<Stroke> helloWorld(String surface) => [
  scribble(
    'hello',
    surface,
    const Rect.fromLTRB(100, 380, 220, 420),
    createdAt: 1,
    color: 0xFFE03131,
  ),
  scribble(
    'world',
    surface,
    const Rect.fromLTRB(250, 380, 380, 420),
    createdAt: 2,
    color: 0xFFE03131,
  ),
];

final fake = FakeRecognizer(words: {'hello': 'hello', 'world': 'world', 'more': 'more'});

Future<List<RecognitionCandidate>> recognize(List<Stroke> line, Size area) =>
    fake.recognize(line, language: 'en-US', writingArea: area);

void main() {
  test('recognises line by line; alternatives for a single line', () async {
    final one = await ConvertToText.recognize(helloWorld('s'), recognize);
    expect(one.text, 'hello world');
    expect(one.alternatives, ['HELLO WORLD']);

    final two = await ConvertToText.recognize([
      ...helloWorld('s'),
      scribble('more', 's', const Rect.fromLTRB(100, 460, 200, 500), createdAt: 3),
    ], recognize);
    expect(two.text, 'hello world\nmore');
    expect(two.alternatives, isEmpty);
  });

  test('the text box sits where the ink was, in its colour and size', () {
    final box = ConvertToText.textBox(
      helloWorld('s'),
      'hello world',
      id: 't',
      surfaceId: 's',
      z: 3,
      createdAt: 5,
    );
    final data = TextData.fromJson(box.data);
    expect(box.rect.topLeft, const Offset(99, 379));
    expect(box.rect.width, greaterThanOrEqualTo(282));
    expect(data.color, 0xFFE03131);
    expect(data.fontSize, closeTo(42 * ConvertToText.fontPerLetterHeight, 1e-6));
    expect(data.text, 'hello world');
    expect(box.z, 3);
  });

  test('replacing the selected strokes is one undoable edit', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final clock = FakeClock();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    );
    addTearDown(model.dispose);
    model.commit(InkEdit(added: helloWorld('s')));
    final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
    addTearDown(selection.dispose);
    selection.select(helloWorld('s').map((s) => model.strokeById(s.id)!), const []);

    final box = ConvertToText.textBox(
      selection.strokes,
      'hello world',
      id: 't',
      surfaceId: 's',
      z: 1,
      createdAt: 1,
    );
    selection.replaceStrokesWith([box]);
    expect(model.strokeById('hello'), isNull);
    expect(model.elementById('t'), isNotNull);
    expect(selection.elements.single.id, 't');

    model.undo();
    expect(model.strokeById('hello'), isNotNull);
    expect(model.strokeById('world'), isNotNull);
    expect(model.elementById('t'), isNull);
    model.redo();
    expect(model.elementById('t'), isNotNull);
  });

  group('editor', () {
    Future<(AppServices, Notebook)> open(WidgetTester tester, FakeRecognizer recognizer) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.inMemory();
      SettingsRepository(db).handwritingIndexing = false; // No background work.
      final services = AppServices.create(db, recognizer: recognizer);
      addTearDown(services.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      final notebook = services.notebooks.create(
        title: 'Board',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0xFF3B5BDB,
      );
      services.strokes.save(helloWorld(notebook.id));
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EditorScreen(notebook: notebook),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (services, notebook);
    }

    Future<void> lassoAll(WidgetTester tester) async {
      await key(tester, LogicalKeyboardKey.keyL);
      await mouseDrag(tester, const [
        Offset(60, 300),
        Offset(460, 300),
        Offset(460, 480),
        Offset(60, 480),
        Offset(60, 310),
      ]);
    }

    testWidgets('lasso → Convert to text → pick an alternative → replace; undo', (tester) async {
      final recognizer = FakeRecognizer(words: {'hello': 'hello', 'world': 'world'});
      final (services, nb) = await open(tester, recognizer);
      await lassoAll(tester);
      await tester.tap(find.byTooltip('Convert to text'));
      await tester.pumpAndSettle();
      expect(find.text('Convert to text'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'hello world'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'HELLO WORLD'));
      await tester.pump();
      await tester.tap(find.text('Replace with text'));
      await tester.pumpAndSettle();

      expect(liveStrokes(services, nb.id), isEmpty);
      final box = liveElements(services, nb.id).single;
      expect(TextData.fromJson(box.data).text, 'HELLO WORLD');
      expect(TextData.fromJson(box.data).color, 0xFFE03131);

      await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
      await tester.pump();
      expect(liveElements(services, nb.id), isEmpty);
      expect(liveStrokes(services, nb.id), hasLength(2));
    });

    testWidgets('copy puts the text on the clipboard and keeps the ink', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (services, nb) = await open(
        tester,
        FakeRecognizer(words: {'hello': 'hello', 'world': 'world'}),
      );
      await lassoAll(tester);
      await tester.tap(find.byTooltip('Convert to text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, 'hello world');
      expect(liveStrokes(services, nb.id), hasLength(2));
    });

    testWidgets('a missing model is offered for download first', (tester) async {
      final recognizer = FakeRecognizer(words: {'hello': 'hello'}, downloaded: false);
      await open(tester, recognizer);
      await lassoAll(tester);
      await tester.tap(find.byTooltip('Convert to text'));
      await tester.pumpAndSettle();
      expect(find.text('Download handwriting model?'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(recognizer.downloads, 1);
      expect(find.text('Convert to text'), findsOneWidget);
    });

    testWidgets('unsupported platforms show the action disabled with a reason', (tester) async {
      await open(tester, FakeRecognizer(supported: false));
      await lassoAll(tester);
      expect(find.byTooltip('Convert to text'), findsNothing);
      expect(find.byTooltip('Not here'), findsOneWidget);
    });
  });
}
