import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/spool_storage.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/audio/recording_journal.dart';
import 'package:len/features/audio/recording_recovery.dart';
import 'package:len/features/audio/ui/recover_recording_dialog.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/real_async.dart';

/// Services with a spool of native-like (raw AAC) recordings.
class _Device {
  _Device() {
    clock.now = DateTime(2024, 3, 5, 14, 5).millisecondsSinceEpoch;
    services = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
    notebook = services.notebooks.create(
      title: 'Biology lecture',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
  }

  final spool = MemorySpoolStorage();
  late final audio = FakeAudio(adts: true, spool: spool);
  final clock = FakeClock();
  late final AppServices services;
  late final Notebook notebook;

  RecordingController controller() => RecordingController(
    notebookId: notebook.id,
    backends: audio.backends,
    blobs: services.blobs,
    repository: services.recordings,
    partMs: 60000,
  );

  RecordingRecovery recovery() =>
      RecordingRecovery(spool: spool, blobs: services.blobs, repository: services.recordings);

  /// Records [first] frames, moves on to a second part (if [split]), records
  /// [second] frames plus half a frame — and the app is killed.
  Future<String> recordAndKill({int first = 0, bool split = false, int second = 0}) async {
    final c = controller();
    await c.start();
    final id = c.recordingId!;
    audio.capture.write(adtsFrames(first));
    if (split) {
      clock.now += 60000;
      await c.nextPartIfDue();
    }
    audio.capture.write(adtsFrames(second));
    audio.capture.write(adtsFrames(1).sublist(0, 8)); // Cut off mid-frame.
    clock.now += 5000;
    // Killed: nothing more happens; the next run knows nothing of it.
    RecordingController.active.clear();
    return id;
  }
}

void main() {
  setUp(RecordingController.active.clear);

  group('recovery', () {
    test('a recording killed in its first part is recovered whole', () async {
      final d = _Device();
      addTearDown(d.services.dispose);
      final id = await d.recordAndKill(second: 50); // 3.2 s.
      expect(d.services.recordings.get(id), isNull); // Nothing stored yet.

      final found = await d.recovery().find();
      expect(found, hasLength(1));
      expect(found.single.unsavedMs, 3200);
      expect(found.single.savedMs, 0);

      final recording = (await d.recovery().recover(found.single))!;
      expect(recording.id, id);
      expect(recording.durationMs, 3200);
      expect(recording.title, 'Recording 14:05');
      expect(recording.mime, Recording.adtsMime);
      expect(recording.segments, [RecordingSegment(d.clock.now - 5000, 3200)]);
      expect(await d.services.blobs.read(recording.parts.single.blob), adtsFrames(50));
      expect(d.spool.files, isEmpty);
      expect(await d.recovery().find(), isEmpty);
    });

    test('the unsaved tail is added to the parts stored before', () async {
      final d = _Device();
      addTearDown(d.services.dispose);
      final id = await d.recordAndKill(first: 900, split: true, second: 25); // 57.6 s + 1.6 s.
      expect(d.services.recordings.get(id)!.durationMs, 57600); // Stored while recording.

      final found = (await d.recovery().find()).single;
      expect((found.savedMs, found.unsavedMs), (57600, 1600));
      final recording = (await d.recovery().recover(found))!;
      expect(recording.parts.map((p) => p.durationMs), [57600, 1600]);
      expect(recording.durationMs, 59200);
      expect(recording.segments.fold(0, (sum, s) => sum + s.durationMs), 59200);
      expect(d.services.recordings.listOf(d.notebook.id).single.id, id);
      expect(d.spool.files, isEmpty);
    });

    test('discard deletes the spool files; stored parts stay', () async {
      final d = _Device();
      addTearDown(d.services.dispose);
      final id = await d.recordAndKill(first: 900, split: true, second: 25);
      await d.recovery().discard((await d.recovery().find()).single);
      expect(d.spool.files, isEmpty);
      expect(d.services.recordings.get(id)!.durationMs, 57600);
    });

    test('recordings being made are left alone; stray files are removed', () async {
      final d = _Device();
      addTearDown(d.services.dispose);
      final c = d.controller();
      await c.start();
      d.audio.capture.write(adtsFrames(10));
      d.spool.files['stray-0.aac'] = adtsFrames(2);
      d.spool.files['broken.json'] = Uint8List.fromList([1]);
      expect(await d.recovery().find(), isEmpty);
      expect(d.spool.files.keys.toSet(), {
        RecordingJournal.nameOf(c.recordingId!),
        '${c.recordingId}-0.aac',
      });
      await c.stop();
      expect(d.spool.files, isEmpty);
      c.dispose();
    });
  });

  testWidgets('on start Len offers to recover a recording cut off', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(900, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final d = _Device();
    addTearDown(d.services.dispose);
    late String id;
    await tester.runAsync(() async {
      id = await d.recordAndKill(first: 2000, split: true, second: 3000); // 2:08 + 3:12.
    });
    resetRecordingRecoveryOffer();
    await tester.pumpWidget(
      AppScope(
        services: d.services,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                offerRecordingRecovery(context, d.services);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('Recover recording?').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Recover recording?'), findsOneWidget);
    expect(find.textContaining('3:12 of audio were not saved yet'), findsOneWidget);
    expect(find.textContaining('The first 2:08 are saved either way'), findsOneWidget);
    await expectLater(find.byType(Dialog), matchesGoldenFile('goldens/audio_recover.png'));

    await tester.tap(find.text('Recover'));
    await pumpUntil(tester, () => find.textContaining('Recovered “').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('Recovered “Recording 14:05” (5:20)'), findsOneWidget);
    expect(d.services.recordings.get(id)!.durationMs, 320000);
    expect(d.spool.files, isEmpty);
  });
}
