import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/waveform.dart';
import 'package:len/features/audio/adts.dart';
import 'package:len/features/audio/ui/recordings_sheet.dart';
import 'package:len/features/documents/export/export_flow.dart' show ExportFile;
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/handwriting.dart';

const _t0 = 1000000;

/// 469 frames of 64 ms: 30 s of raw AAC.
final _audio = adtsFrames(469);

class _Editor {
  _Editor(this.services, this.notebook, this.audio);

  final AppServices services;
  final Notebook notebook;
  final FakeAudio audio;

  Recording get recording => services.recordings.listOf(notebook.id).single;
}

Future<_Editor> _pump(WidgetTester tester, {required Size size, bool dark = false}) async {
  await loadFonts();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final services = AppServices.create(
    AppDatabase.inMemory(),
    clock: FakeClock()..now = _t0 + 60000,
    audio: audio.backends,
  );
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Biology lecture',
    kind: NotebookKind.canvas,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  // A word every 3 s.
  services.strokes.save([
    for (var i = 0; i < 10; i++)
      Stroke(
        id: 's$i',
        surfaceId: nb.id,
        tool: InkTool.ballpoint,
        color: 0xFF1F2937,
        width: 2.6,
        points: Handwriting(seed: i).cursive(Offset(60.0 + (i % 4) * 90, 200.0 + (i ~/ 4) * 60), [
          for (var j = 0; j < 4; j++) (height: j.isEven ? 16.0 : 30.0, loop: 4.0),
        ], letterWidth: 14),
        createdAt: _t0 + 500 + i * 3000,
      ),
  ]);
  final levels = Uint8List.fromList([for (var i = 0; i < 300; i++) 40 + (i * 37) % 200]);
  final waveform = await services.blobs.putFile(
    XFile.fromData(Waveform(levels).encode()),
    mime: Waveform.mime,
  );
  final sha = await services.blobs.putFile(XFile.fromData(_audio), mime: Recording.adtsMime);
  services.recordings.save(
    notebookId: nb.id,
    parts: [RecordingPart(sha, 30000)],
    mime: Recording.adtsMime,
    title: 'Mitosis',
    segments: const [RecordingSegment(_t0, 30000)],
    waveform: waveform,
  );
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Editor(services, nb, audio);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Opens the recordings list (from the top bar, or the "⋯" menu on
/// phones) and picks Trim… from the recording's menu.
Future<void> _trimFromList(WidgetTester tester) async {
  if (find.byTooltip('Recordings').evaluate().isEmpty) {
    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recordings…'));
  } else {
    await tester.tap(find.byTooltip('Recordings'));
  }
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(RecordingsList), matching: find.byTooltip('More')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trim…'));
  await _settle(tester);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('trim: drag the handles, preview, save, undo; list and playback follow', (
    tester,
  ) async {
    final e = await _pump(tester, size: const Size(1280, 800));
    await _trimFromList(tester);
    expect(find.byKey(const ValueKey('trim-panel')), findsOneWidget);
    expect(e.audio.log, ['open Mitosis']); // Opened paused.

    // Drag the start handle 5 s to the right and the end handle 5 s left.
    final start = find.byKey(const ValueKey('trim-start'));
    final end = find.byKey(const ValueKey('trim-end'));
    final track = tester.getSize(find.byKey(const ValueKey('waveform-scrubber'))).width;
    await tester.drag(start, Offset(track / 6, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    await tester.drag(end, Offset(-track / 6, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    final draft = e.recording; // Not saved yet.
    expect(draft.trimmed, isFalse);
    expect(find.text('0:05 – 0:25 · 0:20'), findsOneWidget);
    // After the end moved, the preview is just before it.
    expect(e.audio.log.last, 'seek 23000');
    e.audio.player.emit(23000);
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('playback-bar')),
      matchesGoldenFile('goldens/audio_trim.png'),
    );

    // Preview plays only the kept audio.
    await tester.tap(find.byTooltip('Play the kept audio (Space)'));
    await tester.pump();
    expect(e.audio.log.last, 'play');
    e.audio.player.emit(25200);
    await tester.pump();
    expect(e.audio.log.last, 'pause');

    // Keyboard: the focused start handle moves a second per arrow.
    await tester.tap(start);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('0:04 – 0:25 · 0:21'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final r = e.recording;
    expect((r.trimStartMs, r.trimEndMs), (5000, 25000));
    expect(find.byKey(const ValueKey('trim-panel')), findsNothing);
    expect(find.text('Trimmed “Mitosis” to 0:20'), findsOneWidget);
    expect(find.text('0:00 / 0:20'), findsOneWidget);

    // Playback keeps to the kept audio.
    await tester.tap(find.byTooltip('Play (Space)'));
    await tester.pump();
    e.audio.player.emit(25100);
    await tester.pump();
    expect(e.audio.log.last, 'pause');
    expect(find.text('0:20 / 0:20'), findsOneWidget);

    // Undo from the message restores the whole recording.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(e.recording.trimmed, isFalse);
    expect(find.text('0:25 / 0:30'), findsOneWidget);

    // Trim again (from the player) and check the list and export.
    await tester.tap(find.byTooltip('Trim…'));
    await tester.pumpAndSettle();
    await tester.drag(start, Offset(track / 6, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    await tester.drag(end, Offset(-track / 6, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Recordings').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(' · 0:20'), findsWidgets);
    final list = tester.widget<RecordingsList>(find.byType(RecordingsList));
    List<ExportFile>? exported;
    list.audio.saveFiles = (files, {required mime}) async {
      exported = files;
      return '/home/me/Music';
    };
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await _settle(tester);
    expect(exported!.single.name, 'Mitosis.aac');
    expect(exported!.single.bytes, AdtsReader.cut(_audio, 5000, 25000));
    expect(AdtsReader.readAll(exported!.single.bytes).durationMs, closeTo(20000, 130));

    // Reset trim from the list.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset trim'));
    await tester.pumpAndSettle();
    expect(e.recording.trimmed, isFalse);
    await _dispose(tester);
  });

  for (final (name, size, dark) in [
    ('phone', const Size(390, 844), false),
    ('phone_dark', const Size(390, 844), true),
  ]) {
    testWidgets('trim panel on a $name', (tester) async {
      await _pump(tester, size: size, dark: dark);
      await _trimFromList(tester);
      final start = find.byKey(const ValueKey('trim-start'));
      final track = tester.getSize(find.byKey(const ValueKey('waveform-scrubber'))).width;
      await tester.drag(start, Offset(track / 3, 0), touchSlopX: 0);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(EditorScreen),
        matchesGoldenFile('goldens/audio_trim_$name.png'),
      );
      await _dispose(tester);
    });
  }
}
