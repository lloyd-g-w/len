import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/progress_dialog.dart';

void main() {
  testWidgets('the progress dialog closes when the task ends', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    final done = Completer<int>();
    final result = runWithProgress(context, 'Working', () => done.future);
    await tester.pump(const Duration(milliseconds: 500)); // (The spinner never settles.)
    expect(find.byType(ProgressDialog), findsOneWidget);
    done.complete(3);
    expect(await result, 3);
    await tester.pumpAndSettle();
    expect(find.byType(ProgressDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a progress dialog closed meanwhile leaves the other routes alone', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Library')),
      ),
    );
    late BuildContext editor;
    final editorRoute = MaterialPageRoute<void>(
      builder: (c) {
        editor = c;
        return const Scaffold(body: Text('Editor'));
      },
    );
    unawaited(navigator.currentState!.push(editorRoute));
    await tester.pumpAndSettle();
    final done = Completer<void>();
    final task = runWithProgress(editor, 'Exporting', () => done.future);
    await tester.pump(const Duration(milliseconds: 500));
    // The editor closes with everything over it (its notebook was deleted
    // on another device) while the task still runs.
    navigator.currentState!
      ..popUntil((r) => r == editorRoute)
      ..pop();
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
    done.complete();
    await task;
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget, reason: 'the library was not popped');
  });
}
