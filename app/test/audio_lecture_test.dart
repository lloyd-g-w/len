import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

/// Round 17 (recording a lecture): the recording stays in sight and
/// keeps going wherever the student goes.

const _t0 = 1000000;

class _Editor {
  _Editor(this.services, this.notebook, this.audio, this.clock);

  final AppServices services;
  final Notebook notebook;
  final FakeAudio audio;
  final FakeClock clock;
}

Future<_Editor> _pump(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final clock = FakeClock()..now = _t0;
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Calculus',
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(services, nb, audio, clock);
}

Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('R17-2: focus mode keeps the recording in sight, docked at the bottom', (
    tester,
  ) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    final pill = find.byKey(const ValueKey('recording-pill')).hitTestable();
    expect(tester.getRect(pill).top, lessThan(60)); // In the top bar.

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(pill, findsOneWidget); // Not the faded top bar's.
    expect(tester.getRect(pill).bottom, greaterThan(700)); // Docked at the bottom.
    await tester.tap(find.byTooltip('Pause recording').hitTestable());
    await _settleAsync(tester);
    expect(find.text('Paused').hitTestable(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(tester.getRect(pill).top, lessThan(60));
    e.clock.now += 3000;
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    await _close(tester);
  });

  testWidgets('R17-4: the "Saved" message offers to name the recording', (tester) async {
    final e = await _pump(tester);
    await tester.tap(find.byTooltip('Record audio'));
    await _settleAsync(tester);
    e.clock.now += 3000;
    await tester.tap(find.byTooltip('Stop recording'));
    await _settleAsync(tester);
    expect(find.textContaining('Saved “Recording'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lecture 12 — Integrals');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    final saved = e.services.recordings.listOf(e.notebook.id).single;
    expect(saved.title, 'Lecture 12 — Integrals');
    await _close(tester);
  });
}
