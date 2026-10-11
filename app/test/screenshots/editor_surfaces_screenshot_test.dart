import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/editor/editor_screen.dart';

import '../support/fake_audio.dart';
import 'editor_screenshot_test.dart' show pumpEditor;
import 'editor_surfaces_common.dart';
import 'screenshot_harness.dart';

// Editor surfaces with real fonts, part 1: find in notebook, convert to
// text, audio. Parts 2 and 3 are editor_surfaces{2,3}_screenshot_test.dart.

/// Text boxes on the Physics pages, for the search to find.
void _searchable(AppServices s) {
  final physics = s.notebooks.list().firstWhere((n) => n.title.startsWith('Physics'));
  final pages = s.pages.pagesOf(physics.id);
  s.elements.save([
    textElement('t1', pages[0].id, 'Forces and motion — summary', const Offset(110, 60)),
    textElement('t2', pages[1].id, 'Friction is a force opposing motion', const Offset(110, 520)),
    textElement('t3', pages[2].id, 'Net force = mass × acceleration', const Offset(110, 300)),
  ]);
}

Future<void> _openSearch(WidgetTester tester, String query) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
  await _type(tester, query);
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await settle(tester);
}

/// A canvas with a line of writing, opened, the writing lassoed.
Future<void> _lassoed(
  WidgetTester tester,
  Screen screen,
  ThemeMode mode,
  ShotRecognizer recognizer, {
  double textScale = 1,
}) async {
  final s = bareServices(recognizer: recognizer);
  final board = whiteboard(s);
  await pumpNotebook(tester, s, board, screen: screen, mode: mode, textScale: textScale);
  await lassoCanvas(tester, const Rect.fromLTRB(-170, -120, 190, -60));
}

Future<void> _convert(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Convert to text'));
  await settle(tester);
}

/// Three recordings of the notebook.
void _recordings(AppServices s, String notebookId, int t0) {
  for (final (i, title, ms) in [
    (0, 'Lecture 4 — Kinematics', 3125000),
    (1, 'Office hours', 640000),
    (2, 'Lab briefing', 95000),
  ]) {
    s.recordings.create(
      notebookId: notebookId,
      blob: '$i' * 64,
      mime: 'audio/mp4',
      title: title,
      segments: [RecordingSegment(t0 - (i + 1) * 86400000, ms)],
    );
  }
}

/// A paged notebook with writing on its first page.
Notebook _lecture(AppServices s) {
  final n = s.notebooks.create(
    title: 'Biology lecture',
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF2F9E44,
  );
  s.strokes.save(
    inkLines(s.pages.pagesOf(n.id).first.id, const Offset(100, 150), lines: 7, width: 560),
  );
  return n;
}

void main() {
  setUpAll(loadRealFonts);

  // 1. Find in notebook.
  for (final screen in [phoneScreen, tabletScreen, desktopScreen]) {
    for (final mode in modes) {
      final shot = 'e_search_${screen.name}_${mode.name}';
      testWidgets(shot, (tester) async {
        await guardOverflows(shot, () async {
          await pumpEditor(
            tester,
            size: screen.size,
            dpr: screen.dpr,
            mode: mode,
            phoneInsets: screen.insets,
            before: _searchable,
          );
          await _openSearch(tester, 'force');
          if (screen == phoneScreen) {
            await shoot(tester, '${shot}_folded');
            await tester.tap(find.byTooltip('Show results'));
            await settle(tester);
          }
          await shoot(tester, shot);
          await tester.tap(find.byTooltip('Next (Enter)'));
          await settle(tester);
          await shoot(tester, '${shot}_next');
          await _type(tester, 'zebra');
          expect(find.text('No matches'), findsOneWidget);
          await shoot(tester, '${shot}_none');
        });
      });
    }
  }

  testWidgets('e_search_phone_large_text', (tester) async {
    await guardOverflows('e_search_phone_large_text', () async {
      await pumpEditor(tester, size: phone, dpr: 2, phoneInsets: true, before: _searchable);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await settle(tester);
      await _openSearch(tester, 'force');
      await tester.tap(find.byTooltip('Show results'));
      await settle(tester);
      await shoot(tester, 'e_search_phone_large_text');
      await _type(tester, 'zebra');
      await shoot(tester, 'e_search_phone_large_text_none');
    });
  });

  // 2. Convert to text (lasso → selection menu → dialog).
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = 'e_convert_${screen.name}_${mode.name}';
      testWidgets(shot, (tester) async {
        await guardOverflows(shot, () async {
          await _lassoed(tester, screen, mode, ShotRecognizer());
          await shoot(tester, 'e_lasso_menu_${screen.name}_${mode.name}');
          await _convert(tester);
          expect(find.text('Recognised text'), findsOneWidget);
          await shoot(tester, shot);
          await tester.tap(find.text('Replace ink'));
          await settle(tester);
          await shoot(tester, '${shot}_replaced');
        });
      });
    }
  }

  testWidgets('e_convert_phone_large_text', (tester) async {
    await guardOverflows('e_convert_phone_large_text', () async {
      await _lassoed(tester, phoneScreen, ThemeMode.light, ShotRecognizer(), textScale: 1.3);
      await shoot(tester, 'e_lasso_menu_phone_large_text');
      await _convert(tester);
      await shoot(tester, 'e_convert_phone_large_text');
    });
  });

  for (final (state, recognizer) in [
    ('loading', () => ShotRecognizer(reading: Reading.slow)),
    ('error', () => ShotRecognizer(reading: Reading.fails)),
    ('empty', () => ShotRecognizer(reading: Reading.empty)),
    ('model_missing', () => ShotRecognizer(downloaded: false)),
    ('downloading', () => ShotRecognizer(downloaded: false, download: Reading.slow)),
    ('download_failed', () => ShotRecognizer(downloaded: false, download: Reading.fails)),
  ]) {
    for (final (screen, mode) in [
      (phoneScreen, ThemeMode.light),
      (phoneScreen, ThemeMode.dark),
      (tabletScreen, ThemeMode.light),
    ]) {
      final shot = 'e_convert_${state}_${screen.name}_${mode.name}';
      testWidgets(shot, (tester) async {
        await guardOverflows(shot, () async {
          await _lassoed(tester, screen, mode, recognizer());
          await _convert(tester);
          if (state.startsWith('download')) {
            await tester.tap(find.text('Download'));
            await settle(tester);
          }
          await shoot(tester, shot);
        });
      });
    }
  }

  // 3. Audio.
  for (final mode in modes) {
    final m = mode.name;
    testWidgets('e_audio tablet $m', (tester) async {
      await guardOverflows('e_audio_tablet_$m', () async {
        final audio = FakeAudio();
        final clock = StillClock();
        final s = bareServices(clock: clock, audio: audio.backends);
        final board = whiteboard(s);
        _recordings(s, board.id, clock.now);
        await pumpNotebook(tester, s, board, screen: tabletScreen, mode: mode);
        await tester.tap(find.byTooltip('Record audio'));
        await settle(tester);
        audio.capture.emitLevel(0.7);
        clock.now += 65000;
        await tester.pump(const Duration(milliseconds: 300));
        await shoot(tester, 'e_audio_recording_tablet_$m');
        await tester.tap(find.byTooltip('Pause recording'));
        await settle(tester);
        await shoot(tester, 'e_audio_paused_tablet_$m');
        await tester.tap(find.byTooltip('Stop recording'));
        await settle(tester);
        await shoot(tester, 'e_audio_saved_snack_tablet_$m');
        ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
        await settle(tester);
        await tester.tap(find.byTooltip('Recordings'));
        await settle(tester);
        await shoot(tester, 'e_audio_sheet_tablet_$m');
        await tester.tap(find.text('Office hours'));
        await settle(tester);
        audio.player.emit(222000);
        await settle(tester);
        await shoot(tester, 'e_audio_playback_tablet_$m');
      });
    });

    testWidgets('e_audio phone $m', (tester) async {
      await guardOverflows('e_audio_phone_$m', () async {
        final audio = FakeAudio();
        final clock = StillClock();
        final s = bareServices(clock: clock, audio: audio.backends);
        final nb = _lecture(s);
        _recordings(s, nb.id, clock.now);
        await pumpNotebook(tester, s, nb, screen: phoneScreen, mode: mode);
        await tester.tap(find.byTooltip('More options'));
        await settle(tester);
        await shoot(tester, 'e_audio_phone_menu_$m');
        await tester.tap(find.text('Record audio'));
        await settle(tester);
        audio.capture.emitLevel(0.5);
        clock.now += 754000;
        await tester.pump(const Duration(milliseconds: 300));
        await shoot(tester, 'e_audio_recording_phone_$m');
        await tester.tap(find.byTooltip('Stop recording'));
        await settle(tester);
        ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
        await settle(tester);
        await tester.tap(find.byTooltip('More options'));
        await settle(tester);
        await tester.tap(find.text('Recordings…'));
        await settle(tester);
        await shoot(tester, 'e_audio_sheet_phone_$m');
        await tester.tap(find.text('Lecture 4 — Kinematics'));
        await settle(tester);
        audio.player.emit(1245000);
        await settle(tester);
        await shoot(tester, 'e_audio_playback_phone_$m');
      });
    });
  }

  testWidgets('e_audio phone large text', (tester) async {
    await guardOverflows('e_audio_phone_large_text', () async {
      final audio = FakeAudio();
      final clock = StillClock();
      final s = bareServices(clock: clock, audio: audio.backends);
      final nb = _lecture(s);
      _recordings(s, nb.id, clock.now);
      await pumpNotebook(tester, s, nb, screen: phoneScreen, textScale: 1.3);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Record audio'));
      await settle(tester);
      clock.now += 3725000;
      await tester.pump(const Duration(milliseconds: 300));
      await shoot(tester, 'e_audio_recording_phone_large_text');
      await tester.tap(find.byTooltip('Stop recording'));
      await settle(tester);
      ScaffoldMessenger.of(tester.element(find.byType(EditorScreen))).removeCurrentSnackBar();
      await settle(tester);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.text('Recordings…'));
      await settle(tester);
      await shoot(tester, 'e_audio_sheet_phone_large_text');
      await tester.tap(find.text('Lecture 4 — Kinematics'));
      await settle(tester);
      audio.player.emit(1245000);
      await settle(tester);
      await shoot(tester, 'e_audio_playback_phone_large_text');
    });
  });
}
