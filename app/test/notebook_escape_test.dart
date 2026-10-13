import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';

import 'search_ui_test.dart' show pumpEditorFor;

Future<void> _drag(WidgetTester tester, List<Offset> points) async {
  final gesture = await tester.startGesture(points.first, kind: PointerDeviceKind.mouse);
  for (final p in points.skip(1)) {
    await gesture.moveTo(p);
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  // Found by the desktop e2e suite: the PDF text selection's Escape
  // replaced the lasso's in paged notebooks.
  testWidgets('notebooks: Escape drops the lasso selection', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final nb = services.notebooks.create(
      title: 'Notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0xFF3B5BDB,
    );
    await pumpEditorFor(tester, services, nb, size: const Size(1280, 800));
    final c = tester.getCenter(find.byType(EditorScreen));
    await _drag(tester, [for (var i = 0; i <= 10; i++) c + Offset(i * 20.0, (i % 2) * 10.0)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await _drag(tester, [
      c + const Offset(-40, -40),
      c + const Offset(240, -40),
      c + const Offset(240, 50),
      c + const Offset(-40, 50),
      c + const Offset(-40, -35),
    ]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete (Del)'), findsNothing);
  });
}
