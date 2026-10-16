@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/document/paged_document_view.dart';

import 'screenshot_harness.dart';
import 'toolbar_screenshot_test.dart' show openEditor, phone, tablet;

// The eyedropper ("Pick from page" in a colour picker): its hint, and the
// loupe while a finger rests on the page.

/// Lets the eyedropper's capture of the page (real `toImage`) finish.
Future<void> _capture(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }
  await tester.pump();
}

Offset _onPage(WidgetTester tester, Offset page) {
  final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
  return doc.viewport.toScreen(page + doc.layout.frameOf(0)!.topLeft);
}

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size) in [('tablet', tablet), ('phone', phone)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('eyedropper $name ${mode.name}', (tester) async {
        await openEditor(tester, size, 2, mode);
        await tester.tap(find.byKey(const ValueKey('color-0')));
        await settle(tester);
        await shoot(tester, 'eyedropper_picker_${name}_${mode.name}');
        await tester.tap(find.byKey(const ValueKey('pick-from-page')));
        await settle(tester);
        await _capture(tester);
        await shoot(tester, 'eyedropper_hint_${name}_${mode.name}');
        // On the highlighted word of the first line.
        final gesture = await tester.startGesture(_onPage(tester, const Offset(200, 221)));
        await _capture(tester);
        await shoot(tester, 'eyedropper_loupe_${name}_${mode.name}');
        await gesture.up();
        await settle(tester);
        await shoot(tester, 'eyedropper_picked_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
