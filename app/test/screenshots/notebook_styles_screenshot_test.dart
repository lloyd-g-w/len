import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'screenshot_harness.dart';

/// The new-notebook sheet with saved notebook styles (one the default) and
/// a style's menu, on a phone, a tablet and a desktop, light and dark.
void main() {
  setUpAll(loadRealFonts);

  for (final (device, size, dpr) in [
    ('phone', const Size(390, 844), 2.0),
    ('tablet', const Size(1180, 820), 2.0),
    ('desktop', const Size(1440, 900), 1.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('notebook styles $device ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        final styles = services.notebookStyles;
        final lecture = styles.create(
          name: 'Lecture notes',
          choice: NotebookChoice(
            paper: PaperStyle.cornell,
            format: PageFormat.a5,
            coverColor: Palette.covers[1],
          ),
        );
        styles.create(
          name: 'Sketchbook',
          choice: NotebookChoice(
            kind: NotebookKind.canvas,
            paper: PaperStyle.dotted,
            paperColor: PaperColor.cream,
            coverColor: Palette.covers[2],
          ),
        );
        styles.create(
          name: 'Maths',
          choice: NotebookChoice(paper: PaperStyle.gridSmall, coverColor: Palette.covers[4]),
        );
        styles.setDefault(lecture.id, isDefault: true);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        await tester.tap(newButton());
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_notebook_styles_${device}_${mode.name}');

        // Another choice: "Save as style…" shows under the form.
        await tester.ensureVisible(find.text('Blank'));
        await settle(tester);
        await tester.tap(find.text('Blank'));
        await settle(tester);
        await tester.ensureVisible(find.text('Lecture notes'));
        await settle(tester);
        await shoot(tester, 's_notebook_styles_save_${device}_${mode.name}');

        await tester.longPress(find.text('Lecture notes'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_notebook_styles_menu_${device}_${mode.name}');
      });
    }
  }
}
