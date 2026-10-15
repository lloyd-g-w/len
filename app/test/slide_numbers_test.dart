import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/go_to_page_dialog.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/ui/app_theme.dart';

const _deck = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _handout = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _deck2 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

NotebookPage _page(int i, {String? blob, int pdfPage = 0, bool portrait = false}) => NotebookPage(
  id: 'p$i',
  notebookId: 'n',
  sortKey: i.toDouble(),
  width: blob == null || portrait ? 794 : 960,
  height: blob == null || portrait ? 1123 : 540,
  paper: blob == null ? const Paper(PaperStyle.collegeRuled) : Paper.blank,
  background: blob == null ? null : PageBackground.pdf(blob: blob, pageIndex: pdfPage),
);

/// Slides 1–2, a notes page, slides 3–4: pages 4–5 show "Slide 3" / "4".
final _lecture = [
  _page(0, blob: _deck, pdfPage: 0),
  _page(1, blob: _deck, pdfPage: 1),
  _page(2),
  _page(3, blob: _deck, pdfPage: 2),
  _page(4, blob: _deck, pdfPage: 3),
];

/// A handout's page 5, then two decks: slide 1 is page 2 or page 4.
final _twoDecks = [
  _page(0, blob: _handout, pdfPage: 4, portrait: true),
  _page(1, blob: _deck, pdfPage: 0),
  _page(2, blob: _deck, pdfPage: 1),
  _page(3, blob: _deck2, pdfPage: 0),
  _page(4, blob: _deck2, pdfPage: 1),
];

SurfaceCopier _copier() {
  final s = AppServices.create(AppDatabase.inMemory());
  addTearDown(s.dispose);
  return SurfaceCopier(s.strokes, elements: s.elements);
}

void _size(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens Go to page over [pages] on page [current]; [picked] gets its answer.
Future<void> _goTo(
  WidgetTester tester,
  List<NotebookPage> pages, {
  int current = 0,
  required void Function(int?) picked,
}) async {
  final copier = _copier();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              picked(await showGoToPage(context, pages: pages, current: current, copier: copier)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  // The strip scrolls to the page named.
  await tester.pumpAndSettle();
}

/// Page numbers stay the notebook's; PDF pages show their own number
/// quietly where it differs (UX_AUDIT R18-5).
void main() {
  testWidgets('overview captions: "Slide 3" beside page 4, nothing where equal', (tester) async {
    _size(tester, const Size(1000, 700));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PageOverview(
          currentPage: 3,
          copier: _copier(),
          handlers: OverviewHandlers(
            load: () => _lecture,
            move: (_, _) {},
            command: (_, _, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(' · Slide 3'), findsOneWidget);
    expect(find.text(' · Slide 4'), findsOneWidget);
    expect(find.textContaining('Slide 1'), findsNothing);
    expect(find.textContaining('Slide 2'), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('page-tile-3'))).label,
      startsWith('Page 4, Slide 3, current page'),
    );
    await expectLater(find.byType(PageOverview), matchesGoldenFile('goldens/slide_numbers.png'));
  });

  testWidgets('Go to page: "s3" goes to the page showing slide 3', (tester) async {
    _size(tester, const Size(1000, 800));
    int? result = -1;
    await _goTo(tester, _lecture, picked: (i) => result = i);
    expect(find.text('s3 for Slide 3'), findsOneWidget);
    expect(find.text('4 · Slide 3', findRichText: true, skipOffstage: false), findsOneWidget);
    await _type(tester, 'slide 3');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('go-to-page-4'))),
      isSemantics(label: 'Page 4, Slide 3', isButton: true, isSelected: true),
    );
    await _type(tester, 's9');
    expect(find.text('No slide 9'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Go')).onPressed, isNull);
    // Page numbers are still page numbers.
    await _type(tester, '3');
    expect(find.text('No slide 9'), findsNothing);
    await _type(tester, 's3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 3);
  });

  testWidgets('Go to page: in several PDFs the current one wins, else it asks', (tester) async {
    _size(tester, const Size(1000, 800));
    int? result = -1;
    // On deck 2's page: its slide 1.
    await _goTo(tester, _twoDecks, current: 4, picked: (i) => result = i);
    await _type(tester, 's1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 3);

    // On the handout, which has no page 1: which deck?
    await _goTo(tester, _twoDecks, picked: (i) => result = i);
    await _type(tester, 's1');
    expect(find.text('In 2 PDFs: which one?'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Go')).onPressed, isNull);
    await expectLater(find.byType(GoToPageDialog), matchesGoldenFile('goldens/go_to_slide.png'));
    await tester.tap(find.byKey(const ValueKey('go-to-choice-4')));
    await tester.pumpAndSettle();
    expect(result, 3);
  });

  testWidgets('a plain PDF import or notebook takes numbers only', (tester) async {
    final plain = [for (var i = 0; i < 3; i++) _page(i, blob: _deck, pdfPage: i)];
    await _goTo(tester, plain, picked: (_) {});
    expect(find.textContaining('s1 for'), findsNothing);
    expect(find.textContaining('·'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.number);
  });
}
