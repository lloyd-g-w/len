import 'dart:math' as math;

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
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/domain/waveform.dart';
import 'package:len/features/audio/ui/recordings_sheet.dart';
import 'package:len/features/audio/ui/waveform_scrubber.dart';
import 'package:len/features/documents/export/export_flow.dart' show ExportFile;
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/platform/file_export.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/menus.dart';

import 'content_golden_test.dart' show loadFonts;
import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/handwriting.dart';

/// Recording starts at this wall time.
const _t0 = 1000000;

class _Editor {
  _Editor(this.services, this.notebook, this.audio);

  final AppServices services;
  final Notebook notebook;
  final FakeAudio audio;
}

Future<_Editor> _pump(
  WidgetTester tester, {
  required Future<void> Function(AppServices s, Notebook nb) seed,
  Size size = const Size(1280, 800),
}) async {
  await loadFonts();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final audio = FakeAudio();
  final clock = FakeClock()..now = _t0 + 60000;
  final services = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
  addTearDown(services.dispose);
  final nb = services.notebooks.create(
    title: 'Biology lecture',
    kind: NotebookKind.canvas,
    paper: PaperStyle.wideRuled,
    coverColor: 0xFF3B5BDB,
  );
  await seed(services, nb);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
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
}

Stroke _word(String id, String surface, Offset origin, int at, int seed) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1F2937,
  width: 2.6,
  points: Handwriting(seed: seed).cursive(origin, [
    for (var i = 0; i < 4 + seed % 3; i++) (height: i.isEven ? 16.0 : 34.0, loop: 4.0),
  ], letterWidth: 15),
  createdAt: at,
);

/// Two bursts of writing — four words from 1 s, four more from 18 s — and
/// a text box typed at 12 s, during a 30 s recording with a waveform.
Future<void> _lecture(AppServices s, Notebook nb) async {
  s.strokes.save([
    for (var i = 0; i < 4; i++)
      _word('a$i', nb.id, Offset(160.0 + i * 130, 260), _t0 + 1000 + i * 1500, i),
    for (var i = 0; i < 4; i++)
      _word('b$i', nb.id, Offset(160.0 + i * 130, 330), _t0 + 18000 + i * 1500, i + 4),
  ]);
  s.elements.save([
    SurfaceElement(
      id: 'box',
      surfaceId: nb.id,
      type: ElementType.text.name,
      rect: const Rect.fromLTWH(700, 250, 260, 40),
      z: 1,
      createdAt: _t0 + 12000,
      data: const TextData(text: 'Prophase → metaphase', fontSize: 22).toJson(),
    ),
  ]);
  // Speech with pauses: a few syllables a second, quieter gaps.
  final levels = Uint8List.fromList([
    for (var i = 0; i < 300; i++)
      (i % 50 > 42 ? 20 : 90 + 120 * math.sin(i * 0.9).abs() * (0.6 + 0.4 * math.sin(i * 0.05)))
          .round()
          .clamp(0, 255),
  ]);
  final waveform = await s.blobs.putFile(
    XFile.fromData(Waveform(levels).encode()),
    mime: Waveform.mime,
  );
  s.recordings.save(
    notebookId: nb.id,
    parts: [RecordingPart('cd' * 32, 30000)],
    mime: 'audio/mp4',
    title: 'Mitosis',
    segments: const [RecordingSegment(_t0, 30000)],
    waveform: waveform,
  );
}

Future<void> _open(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Recordings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await _settle(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('player: waveform with ink markers, skip, speed, keyboard, seek by ink', (
    tester,
  ) async {
    final e = await _pump(tester, seed: _lecture);
    await _open(tester, 'Mitosis');
    expect(e.audio.log, ['open Mitosis', 'play']);

    // 10 s in: the first burst is written, the text box (12 s) and the
    // second burst (18 s) are faded.
    e.audio.player.emit(10000);
    await tester.pumpAndSettle();
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/audio_player.png'));

    // Skip ±10 s.
    await tester.tap(find.byTooltip('Forward 10 seconds (→)'));
    await tester.pump();
    expect(e.audio.log.last, 'seek 20000');
    await tester.tap(find.byTooltip('Back 10 seconds (←)'));
    await tester.pump();
    expect(e.audio.log.last, 'seek 10000');

    // Speed.
    await tester.tap(find.byKey(const ValueKey('playback-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: find.text('1.5×'), matching: find.byType(MenuRow<double>)));
    await tester.pumpAndSettle();
    expect(e.audio.log.last, 'rate 1.5');
    expect(find.text('1.5×'), findsOneWidget);

    // Keyboard: Space pauses, → / ← skip (not pages), Shift+→ jumps to the
    // next burst of writing (from just before it began).
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(e.audio.log.last, 'pause');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(e.audio.log.last, 'seek 20000');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(e.audio.log.last, 'seek 10000');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(e.audio.log.last, 'seek ${12000 - 1500}'); // The text box.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(e.audio.log.last, 'seek ${18000 - 1500}'); // The second burst.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(e.audio.log.last, 'seek ${12000 - 1500}');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    // Scrubber: a tap seeks there; a tap on an ink dot plays from it.
    final scrubber = tester.getRect(find.byKey(const ValueKey('waveform-scrubber')));
    await tester.tapAt(Offset(scrubber.left + scrubber.width * 0.8, scrubber.center.dy));
    await tester.pump();
    expect(e.audio.log.last, 'seek 24000');
    await tester.tapAt(Offset(scrubber.left + scrubber.width * 18 / 30 + 6, scrubber.bottom - 4));
    await tester.pump();
    expect(e.audio.log.last, 'seek ${18000 - 1500}');
    // Dragging previews, then seeks once on release.
    final before = e.audio.log.length;
    final drag = await tester.startGesture(
      Offset(scrubber.left + 10, scrubber.top + WaveformScrubber.waveHeight / 2),
    );
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset(scrubber.left + 10 + i * scrubber.width / 20, scrubber.center.dy));
      await tester.pump();
    }
    expect(e.audio.log.length, before);
    await drag.up();
    await tester.pump();
    expect(e.audio.log.last, startsWith('seek '));
    expect(e.audio.log.length, before + 1);

    // Closed player: the keys belong to the editor again.
    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();
    final count = e.audio.log.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(e.audio.log.length, count);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('recordings list: dates, sizes, total; select several to export or delete', (
    tester,
  ) async {
    final e = await _pump(
      tester,
      seed: (s, nb) async {
        for (final (i, title) in ['Intro', 'Cells', 'Mitosis'].indexed) {
          final blob = await s.blobs.putFile(
            XFile.fromData(Uint8List(1536 * (i + 1))),
            mime: 'audio/mp4',
          );
          s.recordings.save(
            notebookId: nb.id,
            parts: [RecordingPart(blob, 125000 * (i + 1))],
            mime: 'audio/mp4',
            title: title,
            // Local times in a past year: the same labels in every time zone.
            segments: [
              RecordingSegment(
                DateTime(2024, 3, 5, 9 + i, 15).millisecondsSinceEpoch,
                125000 * (i + 1),
              ),
            ],
          );
        }
      },
    );
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    expect(find.text('3 recordings · 13 min'), findsOneWidget);
    expect(find.text('5 Mar 2024, 11:15 · 6:15'), findsOneWidget);
    await expectLater(
      find.byType(RecordingsList),
      matchesGoldenFile('goldens/audio_recordings.png'),
    );

    // Long press starts selecting.
    await tester.longPress(find.text('Intro'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Mitosis'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await expectLater(
      find.byType(RecordingsList),
      matchesGoldenFile('goldens/audio_recordings_select.png'),
    );

    // Export both through the save / share path.
    final list = tester.widget<RecordingsList>(find.byType(RecordingsList));
    List<ExportFile>? exported;
    String? exportedMime;
    list.audio.saveFiles = (files, {required mime, toDevice = false}) async {
      exported = files;
      exportedMime = mime;
      return ExportedFiles(ExportedTo.folder, count: files.length, path: '/home/me/Music');
    };
    await tester.tap(find.byTooltip('Share…'));
    await _settle(tester);
    expect(exported!.map((f) => f.name), ['Mitosis.m4a', 'Intro.m4a']);
    expect(exported!.map((f) => f.bytes.length), [4608, 1536]);
    expect(exportedMime, 'audio/mp4');
    expect(find.text('Saved 2 recordings'), findsOneWidget);

    // Delete both (one confirmation).
    await tester.tap(find.byTooltip('Delete…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 recordings?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(e.services.recordings.listOf(e.notebook.id).map((r) => r.title), ['Cells']);
    expect(find.text('1 recording · 4 min'), findsOneWidget);
    expect(find.byTooltip('Select'), findsNothing); // One left: nothing to select.

    // One recording from its ⋯ menu (which shows its size).
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('3 KB on this device'), findsOneWidget);
    await tester.tap(find.text('Share…'));
    await _settle(tester);
    expect(exported!.single.name, 'Cells.m4a');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Android: recordings share or save to device', (tester) async {
    final e = await _pump(
      tester,
      seed: (s, nb) async {
        for (final title in ['Intro', 'Cells']) {
          final blob = await s.blobs.putFile(XFile.fromData(Uint8List(1536)), mime: 'audio/mp4');
          s.recordings.save(
            notebookId: nb.id,
            parts: [RecordingPart(blob, 125000)],
            mime: 'audio/mp4',
            title: title,
            segments: [RecordingSegment(DateTime(2024, 3, 5, 9).millisecondsSinceEpoch, 125000)],
          );
        }
      },
    );
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    final audio = tester.widget<RecordingsList>(find.byType(RecordingsList)).audio;
    final calls = <(int, bool)>[];
    audio
      ..canSaveToDevice = true
      ..saveFiles = (files, {required mime, toDevice = false}) async {
        calls.add((files.length, toDevice));
        return ExportedFiles(ExportedTo.device, count: files.length, name: files.first.name);
      };

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    expect(find.text('Share…'), findsOneWidget);
    await tester.tap(find.text('Save to device…'));
    await _settle(tester);
    expect(calls, [(1, true)]);

    await tester.longPress(find.text('Intro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cells'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share…'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Save to device…'));
    await _settle(tester);
    expect(calls, [(1, true), (2, false), (2, true)]);
    expect(e.services.recordings.listOf(e.notebook.id), hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
