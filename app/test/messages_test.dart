import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/messages.dart';

void main() {
  testWidgets('a snack bar centres on its MessagePane, not the window', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext paneContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 240),
              Expanded(
                child: MessagePane(
                  child: Builder(
                    builder: (context) {
                      paneContext = context;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    showMessage(paneContext, 'Moved');
    await tester.pumpAndSettle();
    final snack = tester.getRect(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
    );
    expect(snack.width, messageMaxWidth);
    expect(snack.center.dx, closeTo(240 + (1440 - 240) / 2, 1));
  });

  testWidgets('a standing notice steps aside while a snack bar shows', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return MessageQueue.stepAside(child: const Text('The PDF is missing'));
            },
          ),
        ),
      ),
    );
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: find.text('The PDF is missing'), matching: find.byType(Opacity)),
        )
        .opacity;
    expect(opacity(), 1);
    showMessage(context, 'Page saved', duration: const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    expect(find.text('Page saved'), findsOneWidget);
    // Replacing the message keeps the notice away; it comes back after.
    showMessage(context, 'Page moved', duration: const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Page moved'), findsNothing);
    expect(opacity(), 1);
  });

  // Found by the desktop e2e suite: Flutter keeps snack bars with an
  // action until dismissed, so "Stylus detected … Undo" and every other
  // Undo message stayed over the page for good.
  testWidgets('a message with an action goes away by itself', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMessage(
                context,
                'Page 2 deleted',
                action: SnackBarAction(label: 'Undo', onPressed: () {}),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 deleted'), findsNothing);
  });

  group('short copy on phones at large text', () {
    Future<void> show(WidgetTester tester, Size size, double scale) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final short = shortMessages(context);
      showMessage(
        context,
        'Stylus detected: fingers now pan and zoom',
        short: 'Fingers now pan',
        action: SnackBarAction(label: short ? 'Undo' : 'Keep finger drawing', onPressed: () {}),
      );
      await tester.pumpAndSettle();
    }

    for (final width in [360.0, 390.0]) {
      testWidgets('a ${width.round()}-dp phone at 2× text: one line beside its action', (
        tester,
      ) async {
        await show(tester, Size(width, 800), 2);
        final semantics = tester.ensureSemantics();
        final text = find.text('Fingers now pan');
        expect(text, findsOneWidget);
        final line = MediaQuery.textScalerOf(tester.element(text)).scale(15) * 1.6;
        expect(tester.getRect(text).height, lessThan(line), reason: 'one line');
        expect(tester.getCenter(find.text('Undo')).dy, closeTo(tester.getCenter(text).dy, 1));
        // Screen readers hear the whole sentence; the action is a button.
        expect(find.bySemanticsLabel('Stylus detected: fingers now pan and zoom'), findsOneWidget);
        expect(
          tester.getSemantics(find.text('Undo')),
          isSemantics(label: 'Undo', isButton: true, hasTapAction: true),
        );
        semantics.dispose();
        if (width == 390) {
          await expectLater(
            find.byType(SnackBar),
            matchesGoldenFile('goldens/message_short_phone_2x.png'),
          );
        }
      });
    }

    testWidgets('phones at normal text and wide windows at large text keep the sentence', (
      tester,
    ) async {
      await show(tester, const Size(390, 800), 1);
      expect(find.text('Stylus detected: fingers now pan and zoom'), findsOneWidget);
      expect(find.text('Keep finger drawing'), findsOneWidget);
      await show(tester, const Size(1280, 800), 2);
      expect(find.text('Stylus detected: fingers now pan and zoom'), findsOneWidget);
      expect(find.text('Keep finger drawing'), findsOneWidget);
    });
  });
}
