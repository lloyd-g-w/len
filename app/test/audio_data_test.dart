import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/backends/record_capture.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/audio/recording_controller.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';
import 'support/fake_server.dart' show FakeServer, apiFor, device;

final _sha = 'ab' * 32;

Notebook _notebook(AppServices s, {NotebookKind kind = NotebookKind.paged}) =>
    s.notebooks.create(title: 'Lecture', kind: kind, paper: PaperStyle.lined, coverColor: 1);

Recording _record(AppServices s, String notebookId, {String title = 'Talk'}) => s.recordings.create(
  notebookId: notebookId,
  blob: _sha,
  mime: 'audio/mp4',
  title: title,
  segments: const [RecordingSegment(10000, 5000), RecordingSegment(20000, 3000)],
);

void main() {
  group('timeline', () {
    final timeline = RecordingTimeline(const [
      RecordingSegment(10000, 5000), // Audio 0–5000 = wall 10000–15000.
      RecordingSegment(20000, 3000), // Audio 5000–8000 = wall 20000–23000.
    ]);

    test('audio position → wall time', () {
      expect(timeline.durationMs, 8000);
      expect(timeline.wallTimeAt(0), 10000);
      expect(timeline.wallTimeAt(4999), 14999);
      expect(timeline.wallTimeAt(5000), 20000);
      expect(timeline.wallTimeAt(6500), 21500);
      expect(timeline.wallTimeAt(99999), 23000); // Clamped to the end.
      expect(timeline.wallTimeAt(-5), 10000);
    });

    test('wall time → audio position; pauses map to the resume point', () {
      expect(timeline.positionOf(9999), isNull);
      expect(timeline.positionOf(10000), 0);
      expect(timeline.positionOf(12500), 2500);
      expect(timeline.positionOf(15000), 5000);
      expect(timeline.positionOf(17000), 5000); // Written during the pause.
      expect(timeline.positionOf(21000), 6000);
      expect(timeline.positionOf(23000), 8000);
      expect(timeline.positionOf(23001), isNull);
      expect(timeline.covers(17000), isTrue);
    });

    test('round trip within segments', () {
      for (final p in [0, 1234, 4999, 5000, 7999]) {
        expect(timeline.positionOf(timeline.wallTimeAt(p)), p);
      }
    });

    test('a recording without segments is one segment', () {
      final r = Recording(
        id: 'r',
        notebookId: 'n',
        blob: _sha,
        durationMs: 4000,
        startedAt: 100,
        title: '',
        mime: 'audio/mp4',
        updatedAt: 1,
      );
      expect(r.segments, [const RecordingSegment(100, 4000)]);
      expect(r.timeline.positionOf(2100), 2000);
    });

    test('segments parse defensively', () {
      expect(RecordingSegment.tryParse([1, 2]), const RecordingSegment(1, 2));
      expect(RecordingSegment.tryParse([1]), isNull);
      expect(RecordingSegment.tryParse(['a', 2]), isNull);
      expect(RecordingSegment.tryParse([1, -2]), isNull);
      expect(RecordingSegment.tryParse(null), isNull);
    });

    test('input level maps dBFS to 0..1', () {
      expect(RecordCapture.levelOf(0), 1);
      expect(RecordCapture.levelOf(-25), 0.5);
      expect(RecordCapture.levelOf(-160), 0);
      expect(RecordCapture.levelOf(double.negativeInfinity), 0);
    });
  });

  group('repository', () {
    late AppServices s;
    setUp(() => s = AppServices.create(AppDatabase.inMemory()));
    tearDown(() => s.dispose());

    test('create, list, rename, delete', () {
      final nb = _notebook(s);
      final other = _notebook(s);
      final r = _record(s, nb.id);
      _record(s, other.id);
      expect(r.durationMs, 8000);
      expect(r.startedAt, 10000);
      expect(s.recordings.listOf(nb.id).single.segments, r.segments);
      s.recordings.rename(r.id, 'Lecture 1');
      expect(s.recordings.get(r.id)!.title, 'Lecture 1');
      s.recordings.delete(r.id);
      expect(s.recordings.listOf(nb.id), isEmpty);
      expect(s.recordings.listOf(other.id), hasLength(1));
      expect(s.recordings.notebookOf(r.id), nb.id); // Tombstones keep it.
    });

    test('deleting a notebook tombstones its recordings; trash keeps them', () {
      final nb = _notebook(s);
      final r = _record(s, nb.id);
      s.notebooks.trash(nb.id);
      expect(s.recordings.listOf(nb.id), hasLength(1));
      s.notebooks.delete(nb.id);
      expect(s.recordings.listOf(nb.id), isEmpty);
      final tombstone = s.recordings.dirtyRecords(10).singleWhere((x) => x.id == r.id);
      expect(tombstone.deleted, isTrue);
    });

    test('duplicating a notebook copies its recordings (same blob)', () {
      final nb = _notebook(s, kind: NotebookKind.canvas);
      final r = _record(s, nb.id);
      final copy = s.notebooks.duplicate(nb.id)!;
      final copied = s.recordings.listOf(copy.id).single;
      expect(copied.id, isNot(r.id));
      expect(copied.blob, r.blob);
      expect(copied.segments, r.segments);
      expect(copied.title, r.title);
      expect(s.recordings.listOf(nb.id).single.id, r.id);
      expect(s.recordings.dirtyRecords(10).map((x) => x.id), contains(copied.id));
    });

    test('the migration is idempotent', () {
      final nb = _notebook(s);
      _record(s, nb.id);
      final db = s.database.db;
      final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
      // Re-run the last migration over the existing table.
      db.execute('PRAGMA user_version = ${version - 1}');
      AppDatabase.fromConnection(db);
      expect(db.select('PRAGMA user_version').first.columnAt(0), version);
      expect(s.recordings.listOf(nb.id), hasLength(1));
    });
  });

  test('recordings sync between devices: create, rename, delete', () async {
    final server = FakeServer();
    final a = device(server);
    final b = device(server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final nb = _notebook(a);
    final r = _record(a, nb.id);
    await a.sync.engine.sync(apiFor(server));
    var changes = await b.sync.engine.sync(apiFor(server));
    expect(changes.recordingsOfNotebooks, {nb.id});
    final got = b.recordings.listOf(nb.id).single;
    expect(
      (got.id, got.blob, got.durationMs, got.startedAt, got.title, got.mime),
      (r.id, _sha, 8000, 10000, 'Talk', 'audio/mp4'),
    );
    expect(got.segments, r.segments);

    b.recordings.rename(r.id, 'Renamed');
    await b.sync.engine.sync(apiFor(server));
    changes = await a.sync.engine.sync(apiFor(server));
    expect(changes.recordingsOfNotebooks, {nb.id});
    expect(a.recordings.get(r.id)!.title, 'Renamed');

    a.notebooks.delete(nb.id);
    await a.sync.engine.sync(apiFor(server));
    changes = await b.sync.engine.sync(apiFor(server));
    expect(changes.recordingsOfNotebooks, {nb.id});
    expect(b.recordings.listOf(nb.id), isEmpty);
  });

  test('remote recordings: malformed skipped, missing optional fields defaulted', () {
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    SyncRecord record(String id, Map<String, Object?> data) => SyncRecord(
      collection: 'recordings',
      id: id,
      updatedAt: 5,
      deviceId: 'other',
      deleted: false,
      data: data,
    );
    expect(
      () => s.recordings.applyRemote(record('bad', {'notebookId': 'n', 'blob': 'nope'})),
      throwsFormatException,
    );
    s.recordings.applyRemote(
      record('ok', {
        'notebookId': 'n',
        'blob': _sha,
        'durationMs': 3000,
        'startedAt': 50,
        'future': {'x': 1},
        'segments': [
          [50, 1000],
          'junk',
          [2000, 2000],
        ],
      }),
    );
    final r = s.recordings.get('ok')!;
    expect(r.title, '');
    expect(r.mime, 'audio/mp4');
    expect(r.segments, const [RecordingSegment(50, 1000), RecordingSegment(2000, 2000)]);
    final pushed = s.recordings.rowToRecord(
      s.database.db.select("SELECT * FROM recordings WHERE id = 'ok'").first,
    );
    expect(jsonEncode(pushed.data!['segments']), '[[50,1000],[2000,2000]]');
  });

  group('controllers', () {
    late AppServices s;
    late FakeAudio audio;
    late FakeClock clock;
    setUp(() {
      audio = FakeAudio();
      clock = FakeClock()..now = 100000;
      s = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
    });
    tearDown(() => s.dispose());

    RecordingController recorder(String notebookId) => RecordingController(
      notebookId: notebookId,
      backends: audio.backends,
      blobs: s.blobs,
      repository: s.recordings,
    );

    test('record with a pause: segments follow the wall clock', () async {
      final nb = _notebook(s);
      final c = recorder(nb.id);
      expect(await c.start(), isTrue);
      expect(c.state, RecorderState.recording);
      audio.capture.emitLevel(0.7);
      expect(c.level, 0.7);
      clock.now += 4000;
      expect(c.elapsedMs, 4000);
      await c.pause();
      clock.now += 10000; // Paused: not counted.
      expect(c.elapsedMs, 4000);
      await c.resume();
      clock.now += 2000;
      final saved = await c.stop();
      expect(saved, isNotNull);
      expect(saved!.segments, const [
        RecordingSegment(100000, 4000),
        RecordingSegment(114000, 2000),
      ]);
      expect(saved.durationMs, 6000);
      expect(await s.blobs.has(saved.blob), isTrue);
      expect(audio.capture.discarded, hasLength(1)); // Temporary file removed.
      expect(c.state, RecorderState.idle);
      expect(audio.log, ['permission', 'start', 'pause', 'resume', 'stop']);
      c.dispose();
    });

    test('refused permission, unavailable tools and too-short recordings', () async {
      final nb = _notebook(s);
      final refused = FakeAudio(allow: false);
      final c1 = RecordingController(
        notebookId: nb.id,
        backends: refused.backends,
        blobs: s.blobs,
        repository: s.recordings,
      );
      expect(await c1.start(), isFalse);
      expect(c1.lastError, contains('Microphone'));
      expect(c1.state, RecorderState.idle);

      final missing = FakeAudio(unavailable: 'Recording needs ffmpeg.');
      final c2 = RecordingController(
        notebookId: nb.id,
        backends: missing.backends,
        blobs: s.blobs,
        repository: s.recordings,
      );
      expect(await c2.start(), isFalse);
      expect(c2.lastError, 'Recording needs ffmpeg.');

      final c3 = recorder(nb.id);
      await c3.start();
      clock.now += 200;
      expect(await c3.stop(), isNull);
      expect(s.recordings.listOf(nb.id), isEmpty);
      for (final c in [c1, c2, c3]) {
        c.dispose();
      }
    });

    test('playback: wall time follows the position; seeking to ink', () async {
      final nb = _notebook(s);
      final r = _record(s, nb.id);
      final p = PlaybackController(
        backends: audio.backends,
        blobs: s.blobs,
        fetch: (_) async => true,
      );
      expect(await p.open(r), isTrue);
      expect(p.playing, isTrue);
      expect(p.wallTime, 10000);
      audio.player.emit(6000);
      expect(p.wallTime, 21000);
      // A stroke written 3 s into the recording: play from 1.5 s before.
      expect(await p.seekToInk(13000), isTrue);
      expect(p.positionMs, 3000 - PlaybackController.leadMs);
      expect(audio.log.last, 'seek 1500');
      // Written during the pause: from just before the resume.
      expect(await p.seekToInk(17000), isTrue);
      expect(p.positionMs, 5000 - PlaybackController.leadMs);
      // Written before the recording: no jump.
      expect(await p.seekToInk(5000), isFalse);
      audio.player.finish();
      expect(p.playing, isFalse);
      expect(p.positionMs, 8000);
      p.close();
      expect(p.recording, isNull);
      expect(p.wallTime, isNull);
      p.dispose();
    });
  });
}
