import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/features/editor/editor_canvas.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/editor_session.dart';
import 'package:len/features/editor/zoom/zoom_box.dart';
import 'package:len/features/editor/zoom/zoom_box_rail.dart';
import 'package:len/features/editor/zoom/zoom_window.dart';
import 'package:len/ui/app_theme.dart';

/// The editor's session.
EditorSession zoomSession(WidgetTester tester) =>
    tester.widget<EditorCanvas>(find.byType(EditorCanvas)).session;

/// Opens the zoom window with its shortcut.
Future<ZoomWindow> openZoom(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
  await tester.pumpAndSettle();
  return zoomSession(tester).zoomWindow;
}

/// The box's paper on the screen (beside its rail).
Rect boxPaper(WidgetTester tester) {
  final zoom = zoomSession(tester).zoomWindow;
  final box = boxRect(tester);
  final rail = tester.getRect(find.byWidgetPredicate((w) => w is ZoomBoxRail));
  final left = rail.left <= box.left + 1 ? rail.right : box.left;
  return Offset(left, box.top + Hairline.width) & zoom.box;
}

/// A short stylus stroke in the box's paper, from [at] (a fraction of its
/// size, from the bottom left) [length] pixels to the right.
Future<void> writeInBox(WidgetTester tester, Offset at, {double length = 40}) async {
  final paper = boxPaper(tester);
  final start = Offset(paper.left + paper.width * at.dx, paper.bottom - paper.height * at.dy);
  final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await pen.moveTo(start + Offset(length * i / 8, i.isEven ? 6 : -6));
  }
  await pen.up();
  await tester.pump();
}

/// Opens [notebook] in an editor again (after `closeEditor`).
Future<void> reopenEditor(WidgetTester tester, AppServices services, Notebook notebook) async {
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
}

/// The box on the screen.
Rect boxRect(WidgetTester tester) => tester.getRect(find.byType(ZoomBox));
