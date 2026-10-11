import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_references.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/waveform.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/audio/recording_controller.dart';
import 'package:len/features/audio/recording_export.dart';
import 'package:len/features/audio/recording_overview.dart';
import 'package:len/features/audio/ui/audio_format.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

void main() {
  group('waveform', () {
    test('encodes and decodes; junk is rejected', () {
      final w = Waveform(Uint8List.fromList([0, 10, 255, 128]));
      final bytes = w.encode();
      expect(bytes.sublist(0, 4), [0x4C, 0x57, 1, 10]);
      final back = Waveform.decode(bytes)!;
      expect(back.levels, [0, 10, 255, 128]);
      expect(back.bucketMs, 100);
      expect(back.durationMs, 400);
      expect(Waveform.decode(Uint8List.fromList([1, 2, 3])), isNull);
      expect(Waveform.decode(Uint8List.fromList([0x4C, 0x57, 9, 10])), isNull);
      expect(Waveform.decode(Uint8List.fromList([0x4C, 0x57, 1, 0])), isNull);
    });

    test('bars take the loudest bucket they cover', () {
      final w = Waveform(Uint8List.fromList([0, 51, 255, 102, 0, 0, 204, 0]));
      expect(w.bars(4, durationMs: 800), [0.2, 1.0, 0.0, 0.8]);
      // More bars than buckets: each bucket fills several.
      expect(w.bars(16, durationMs: 800).take(4), [0.0, 0.0, 0.2, 0.2]);
      // Audio longer than the waveform: the rest is silent.
      expect(w.bars(2, durationMs: 1600), [1.0, 0.0]);
      expect(w.bars(0, durationMs: 800), isEmpty);
    });

    test('the builder keeps peaks per bucket and fills gaps', () {
      final b = WaveformBuilder()
        ..add(0, 0.2)
        ..add(50, 0.6) // Same bucket: the louder one counts.
        ..add(320, 1.0) // Buckets 1 and 2 got no level.
        ..add(-5, 1); // Ignored.
      expect(b.build(500).levels, [153, 153, 153, 255, 255]);
    });
  });

  group('ink activity', () {
    final ink = InkActivity([30000, 1000, 2000, 2500, 9000, 9500, 31000]);

    test('bursts of writing become markers', () {
      expect(ink.positions.first, 1000);
      expect(ink.markers, [1000, 9000, 30000]);
    });

    test('density is relative to the busiest slice', () {
      expect(ink.density(4, durationMs: 40000), [1.0, 0.0, 0.0, 0.4]);
      expect(InkActivity.none.density(3, durationMs: 1000), [0.0, 0.0, 0.0]);
    });

    test('next / previous marker', () {
      expect(ink.nextMarker(0), 1000);
      expect(ink.nextMarker(1000), 9000); // At a marker: the next one.
      expect(ink.nextMarker(30000), isNull);
      expect(ink.previousMarker(9500), 1000); // Just passed 9 s: one more back.
      expect(ink.previousMarker(20000), 9000);
      expect(ink.previousMarker(1500), isNull);
    });

    test('maps wall times through pauses; times outside are dropped', () {
      final timeline = RecordingTimeline(const [
        RecordingSegment(10000, 5000),
        RecordingSegment(20000, 3000),
      ]);
      expect(InkActivity.of(timeline, [9000, 12000, 17000, 21000, 30000]).positions, [
        2000,
        5000, // Written in the pause: where recording resumed.
        6000,
      ]);
    });
  });

  test('a recording stores its waveform as a blob, referenced and synced', () async {
    final audio = FakeAudio();
    final clock = FakeClock()..now = 100000;
    final s = AppServices.create(AppDatabase.inMemory(), clock: clock, audio: audio.backends);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.canvas,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    final c = RecordingController(
      notebookId: nb.id,
      backends: audio.backends,
      blobs: s.blobs,
      repository: s.recordings,
    );
    await c.start();
    audio.capture.emitLevel(0.5);
    clock.now += 250;
    audio.capture.emitLevel(1);
    clock.now += 50;
    await c.pause();
    audio.capture.emitLevel(0.9); // Paused: not part of the audio.
    clock.now += 5000;
    await c.resume();
    clock.now += 300;
    final saved = (await c.stop())!;
    expect(saved.waveform, hasLength(64));
    final waveform = Waveform.decode((await s.blobs.read(saved.waveform))!)!;
    expect(waveform.levels, [128, 128, 255, 255, 255, 255]);
    expect(BlobReferences(s.database).all(), containsAll([saved.blob, saved.waveform]));
    final record = s.recordings.rowToRecord(
      s.database.db.select('SELECT * FROM recordings WHERE id = ?', [saved.id]).first,
    );
    expect(record.data!['waveform'], saved.waveform);
    c.dispose();
  });

  test('formats: speed, recording time, export names', () {
    expect(PlaybackController.rates.map(formatRate), ['0.75×', '1×', '1.25×', '1.5×', '2×']);
    final now = DateTime(2026, 10, 11, 18);
    int at(DateTime t) => t.millisecondsSinceEpoch;
    expect(formatRecordedAt(at(DateTime(2026, 10, 11, 9, 5)), now: now), 'Today, 09:05');
    expect(formatRecordedAt(at(DateTime(2026, 10, 10, 23, 59)), now: now), 'Yesterday, 23:59');
    expect(formatRecordedAt(at(DateTime(2026, 3, 3, 14, 0)), now: now), '3 Mar, 14:00');
    expect(formatRecordedAt(at(DateTime(2025, 12, 31, 8, 30)), now: now), '31 Dec 2025, 08:30');
    Recording r(String title, String mime) => Recording(
      id: title,
      notebookId: 'n',
      blob: 'ab' * 32,
      durationMs: 1,
      startedAt: 0,
      title: title,
      mime: mime,
      updatedAt: 0,
    );
    expect(
      recordingFileNames([
        r('Lecture', 'audio/mp4'),
        r('Lecture', 'audio/mp4'),
        r('Web', 'audio/webm'),
        r('a/b', 'audio/wav'),
      ]),
      ['Lecture.m4a', 'Lecture (2).m4a', 'Web.webm', isNot(contains('/'))],
    );
  });
}
