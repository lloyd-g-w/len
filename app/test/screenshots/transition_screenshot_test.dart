@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/features/library/notebook_cover.dart';

import 'screenshot_harness.dart';

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);

/// The cover of the library card titled [title].
Finder coverOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(NotebookCard)),
  matching: find.byType(NotebookCover),
);

/// Frames of the "open notebook" transition: the cover grows into the
/// editor (at 15 %, 40 % and 80 % of the way) and shrinks back on close.
void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr) in [
    ('tablet', tablet, 1.0),
    ('tablet_portrait', tabletPortrait, 1.0),
    ('phone', phone, 2.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('open transition $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        final shot = 'open_${name}_${mode.name}';

        await tester.ensureVisible(coverOf('Ideas'));
        await settle(tester);

        // Forward: 400 ms.
        await tester.tap(coverOf('Ideas'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await shoot(tester, '${shot}_15');
        await tester.pump(const Duration(milliseconds: 100));
        await shoot(tester, '${shot}_40');
        await tester.pump(const Duration(milliseconds: 160));
        await shoot(tester, '${shot}_80');
        await settle(tester);
        expect(find.byType(EditorScreen), findsOneWidget);
        await shoot(tester, '${shot}_100');

        // Back: 300 ms, into the cover.
        await tester.tap(find.byTooltip('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await shoot(tester, '${shot}_back_50');
        await settle(tester);
        expect(find.byType(EditorScreen), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
