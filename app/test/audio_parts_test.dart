import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_references.dart';
import 'package:len/data/spool_storage.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/adts.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/audio/recording_export.dart';
import 'package:len/features/audio/recording_journal.dart';
import 'package:len/sync/sync_api.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/fake_server.dart';

final _a = 'aa' * 32, _b = 'bb' * 32, _c = 'cc' * 32;

void main() {
  group('ADTS', () {
    test('counts frames and their audio, in any chunks', () {
      final bytes = adtsFrames(10); // 10 × 64 ms at 16 kHz.
      final whole = AdtsReader.readAll(bytes);
      expect(whole.durationMs, 640);
      expect(whole.frames, bytes);

      final reader = AdtsReader();
      final out = BytesBuilder();
      for (var i = 0; i < bytes.length; i += 5) {
        out.add(reader.add(bytes.sublist(i, i + 5 > bytes.length ? bytes.length : i + 5)));
      }
      expect(reader.frames, 10);
      expect(reader.durationMs, 640);
      expect(out.takeBytes(), bytes);
      expect(AdtsReader.readAll(adtsFrames(3, sampleRate: 48000)).durationMs, 64);
    });

    test('a file cut off mid-frame keeps its whole frames; junk is skipped', () {
      final bytes = adtsFrames(4);
      final cut = AdtsReader.readAll(bytes.sublist(0, bytes.length - 3));
      expect(cut.durationMs, 192);
      expect(cut.frames, bytes.sublist(0, 48));
      final junk = Uint8List.fromList([1, 2, 0xFF, 3, ...adtsFrames(2), 9]);
      expect(AdtsReader.readAll(junk).frames, adtsFrames(2));
    });

    test('files join by concatenation', () async {
      final joined = Uint8List.fromList([...adtsFrames(5), ...adtsFrames(3, sampleRate: 8000)]);
      expect(AdtsReader.readAll(joined).durationMs, 320 + 384);
      expect(
        await AdtsReader.measure(Stream.fromIterable([joined.sublist(0, 7), joined.sublist(7)])),
        704,
      );
    });
  });

  test('parts: positions map to a part and an offset into it', () {
    final parts = [RecordingPart(_a, 1000), RecordingPart(_b, 500), RecordingPart(_c, 2000)];
    expect(parts.startOf(0), 0);
    expect(parts.startOf(2), 1500);
    expect(parts.partAt(0), (index: 0, offsetMs: 0));
    expect(parts.partAt(999), (index: 0, offsetMs: 999));
    expect(parts.partAt(1000), (index: 1, offsetMs: 0)); // A boundary: the later part.
    expect(parts.partAt(1600), (index: 2, offsetMs: 100));
    expect(parts.partAt(9999), (index: 2, offsetMs: 2000)); // Clamped.
    expect(parts.partAt(-5), (index: 0, offsetMs: 0));
  });

  group('journal', () {
    final journal = RecordingJournal(
      recordingId: 'r',
      notebookId: 'n',
      title: 'Recording 09:00',
      mime: Recording.adtsMime,
      parts: [RecordingPart(_a, 1000)],
      segments: const [RecordingSegment(100, 600), RecordingSegment(2000, 300)],
      openSince: 5000,
      files: const ['r-1.aac'],
      waveform: _b,
    );

    test('round trip; malformed is null', () {
      final back = RecordingJournal.tryDecode(journal.encode())!;
      expect(back.encode(), journal.encode());
      expect(back.parts, journal.parts);
      expect(back.openSince, 5000);
      expect(RecordingJournal.tryDecode(Uint8List.fromList([1, 2])), isNull);
    });

    test('timeline matches the audio', () {
      // The running stretch takes what the closed ones don't cover.
      expect(journal.timelineFor(1500), const [
        RecordingSegment(100, 600),
        RecordingSegment(2000, 300),
        RecordingSegment(5000, 600),
      ]);
      // Less audio than the stretches: cut at the end.
      expect(journal.timelineFor(700), const [
        RecordingSegment(100, 600),
        RecordingSegment(2000, 100),
      ]);
      // Paused: the last stretch is lengthened.
      final paused = journal.copyWith(openSince: () => null);
      expect(paused.timelineFor(1000), const [
        RecordingSegment(100, 600),
        RecordingSegment(2000, 400),
      ]);
    });
  });

  test('export: raw AAC parts join into one file, others export as parts', () {
    Recording r(String title, String mime, int parts) => Recording(
      id: title,
      notebookId: 'n',
      parts: [for (var i = 0; i < parts; i++) RecordingPart('$i' * 64, 10)],
      durationMs: 10 * parts,
      startedAt: 0,
      title: title,
      mime: mime,
      updatedAt: 0,
    );
    final aac = r('Lecture', Recording.adtsMime, 3);
    final webm = r('Talk', 'audio/webm', 2);
    expect(aac.joinable, isTrue);
    expect(webm.joinable, isFalse);
    expect(exportGroups(aac), [aac.blobs.toList()]);
    expect(exportGroups(webm), hasLength(2));
    expect(recordingFileNames([aac, webm]), ['Lecture.aac', 'Talk.webm', 'Talk (part 2).webm']);
  });

  group('recording in parts', () {
    late FakeServer server;
    late AppServices s;
    late FakeAudio audio;
    late MemorySpoolStorage spool;
    late FakeClock clock;
    late Notebook nb;

    setUp(() {
      server = FakeServer();
      spool = MemorySpoolStorage();
      audio = FakeAudio(adts: true, spool: spool);
      clock = FakeClock()..now = 100000;
      s = AppServices.create(
        AppDatabase.inMemory(),
        clock: clock,
        audio: audio.backends,
        syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      nb = s.notebooks.create(
        title: 'Lecture',
        kind: NotebookKind.canvas,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      RecordingController.active.clear();
    });
    tearDown(() => s.dispose());

    RecordingController controller() => RecordingController(
      notebookId: nb.id,
      backends: audio.backends,
      blobs: s.blobs,
      repository: s.recordings,
      partMs: 1000,
    );

    RecordingJournal journal() => RecordingJournal.tryDecode(
      spool.files.entries.singleWhere((e) => RecordingJournal.isJournal(e.key)).value,
    )!;

    test('finished parts are stored, referenced and synced before stop', () async {
      final c = controller();
      expect(await c.start(), isTrue);
      final id = c.recordingId!;
      expect(journal().files, ['$id-0.aac']);
      expect(audio.capture.paths, ['spool/$id-0.aac']);

      audio.capture.write(adtsFrames(15)); // 960 ms.
      clock.now += 900;
      await c.nextPartIfDue();
      expect(audio.log.where((l) => l == 'split'), isEmpty); // Not yet.
      clock.now += 100;
      audio.capture.write(adtsFrames(1));
      await c.nextPartIfDue();
      expect(audio.log.last, 'split');
      expect(audio.capture.paths.last, 'spool/$id-1.aac');

      // The part is a blob, in the (unlisted) recording, referenced and
      // uploaded while recording continues.
      final row = s.recordings.get(id)!;
      expect(row.parts, hasLength(1));
      expect(row.durationMs, 1024);
      expect(row.mime, Recording.adtsMime);
      final sha = row.parts.single.blob;
      expect(BlobReferences(s.database).all(), contains(sha));
      expect(spool.files.keys, ['$id.json']); // The finished file is gone.
      expect(journal().files, ['$id-1.aac']);
      expect(journal().parts, row.parts);
      await s.sync.syncNow();
      expect(server.blobs.keys, contains(sha));
      expect(server.stored('recordings', id), isNotNull);
      expect(c.state, RecorderState.recording);

      audio.capture.write(adtsFrames(5));
      clock.now += 300;
      final saved = (await c.stop())!;
      expect(saved.id, id);
      expect(saved.parts.map((p) => p.durationMs), [1024, 320]);
      expect(saved.durationMs, 1344);
      expect(saved.segments.fold(0, (sum, x) => sum + x.durationMs), 1344);
      expect(await s.blobs.read(saved.parts.last.blob), adtsFrames(5));
      expect(spool.files, isEmpty); // Journal and files gone.
      expect(RecordingController.active, isEmpty);
      c.dispose();
    });

    test('pause waits for a split (it may restart the recorder); no split while pausing', () async {
      final c = controller();
      expect(await c.start(), isTrue);
      audio.capture.write(adtsFrames(16));
      clock.now += 1000;
      final restarted = Completer<void>();
      audio.capture.holdSplit = restarted.future;
      final split = c.nextPartIfDue();
      await pumpEventQueue();
      expect(audio.log.last, 'split');
      final paused = c.pause(); // Pressed while the recorder restarts.
      await pumpEventQueue();
      expect(audio.log.last, 'split'); // Paused only once it runs again.
      restarted.complete();
      await split;
      expect(await paused, isTrue);
      expect(audio.log.last, 'pause');
      expect(c.state, RecorderState.paused);

      // Nor does a split start while a pause is under way.
      clock.now += 5000; // Paused: not counted.
      expect(await c.resume(), isTrue);
      clock.now += 1000; // A part's worth again.
      final pausedAgain = c.pause();
      await c.nextPartIfDue();
      expect(await pausedAgain, isTrue);
      expect(audio.log.where((l) => l == 'split'), hasLength(1));
      expect(audio.log.last, 'pause');
      await c.stop();
      c.dispose();
    });
  });
}
