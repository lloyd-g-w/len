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
}
