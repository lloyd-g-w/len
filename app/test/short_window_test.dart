import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'document_editor_test.dart' show closeEditor, pumpEditor;
import 'ui_library_test.dart' show pumpLibrary;

/// A phone held sideways: the shortest window the app lays out for.
const _sideways = Size(844, 390);

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens [open], checks nothing overflowed, then closes it with [close].
Future<void> _check(
  WidgetTester tester,
  String what,
  Future<void> Function() open, {
  Future<void> Function()? close,
}) async {
  await open();
  expect(tester.takeException(), isNull, reason: what);
  if (close != null) {
    await close();
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('a phone held sideways: the library and its sheets fit', (tester) async {
    await pumpLibrary(tester, size: _sideways);
    expect(tester.takeException(), isNull, reason: 'empty library');
    await _check(
      tester,
      'new notebook',
      () async {
        await tester.tap(find.widgetWithText(FilledButton, 'New notebook'));
        await tester.pumpAndSettle();
      },
      close: () async {
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      },
    );
    await _check(tester, 'keyboard shortcuts', () => _ctrl(tester, LogicalKeyboardKey.slash));
  });

  testWidgets('a phone held sideways: the editor and its dialogs fit', (tester) async {
    await pumpEditor(tester, size: _sideways);
    expect(tester.takeException(), isNull, reason: 'editor');
    await _check(tester, 'more menu', () async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    });
    await _check(tester, 'go to page', () => _ctrl(tester, LogicalKeyboardKey.keyG));
    await _check(tester, 'export', () => _ctrl(tester, LogicalKeyboardKey.keyE));
    await _check(tester, 'search', () => _ctrl(tester, LogicalKeyboardKey.keyF));
    await _check(tester, 'keyboard shortcuts', () => _ctrl(tester, LogicalKeyboardKey.slash));
    await _check(
      tester,
      'page overview',
      () async {
        await tester.tap(find.byTooltip('All pages'));
        await tester.pumpAndSettle();
      },
      close: () async {
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      },
    );
    await _check(tester, 'pen options', () async {
      await tester.tap(find.byTooltip('Pen (P)'));
      await tester.pumpAndSettle();
    });
    await _check(tester, 'text box', () async {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.tapAt(const Offset(400, 220));
      await tester.pumpAndSettle();
    });
    await closeEditor(tester);
  });
}
