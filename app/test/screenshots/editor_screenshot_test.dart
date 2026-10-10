import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_screen.dart';

import 'screenshot_harness.dart';

/// The editor around a paged notebook and a canvas, for reviewing the
/// chrome next to the library (owned by the editor; rendered here only).
void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr) in [
    ('phone', const Size(390, 844), 2.0),
    ('tablet', const Size(1280, 800), 1.0),
  ]) {
    for (final title in ['Physics — Mechanics', 'Whiteboard']) {
      testWidgets('editor $name $title', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = seededServices();
        addTearDown(s.dispose);
        final nb = s.notebooks.list().firstWhere((n) => n.title == title);
        await pumpApp(tester, s, EditorScreen(notebook: nb));
        await shoot(tester, 'editor_${name}_${nb.kind.name}');
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
    }
  }
}
