import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'library_ui_test.dart' show addNotebook, pumpSeeded;

/// Recordings are seen from the library (UX_AUDIT R7-10).
void main() {
  testWidgets('a mic marks cards with recordings; search finds their titles', (tester) async {
    final s = await pumpSeeded(tester, (s) {
      final physics = addNotebook(s, 'Physics');
      addNotebook(s, 'Biology');
      for (final title in ['Lecture 4', 'Lab talk']) {
        s.recordings.save(
          notebookId: physics.id,
          parts: [RecordingPart('ab' * 32, 1000)],
          mime: 'audio/mp4',
          title: title,
          segments: const [RecordingSegment(0, 1000)],
        );
      }
    });
    Finder cardOf(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(NotebookCard));
    expect(
      find.descendant(of: cardOf('Physics'), matching: find.byIcon(Symbols.mic_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardOf('Biology'), matching: find.byIcon(Symbols.mic_rounded)),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'lecture 4');
    await tester.pumpAndSettle();
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Biology'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List').last);
    await tester.pumpAndSettle();
    expect(s.preferences.libraryLayout, LibraryLayout.list);
    expect(find.textContaining('1 page, 2 recordings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
