import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/adts.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/audio/recording_export.dart';
import 'package:len/features/audio/trim_range.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

/// 30 s recorded from wall time 10 000 with a 5 s pause after 10 s:
/// audio 0…10 s = wall 10 000…20 000, audio 10…30 s = wall 25 000…45 000.
Recording _lecture({int trimStart = 0, int? trimEnd, String mime = Recording.adtsMime}) =>
    Recording(
      id: 'r',
      notebookId: 'n',
      parts: [RecordingPart('ab' * 32, 30000)],
      durationMs: 30000,
      startedAt: 10000,
      title: 'Lecture',
      mime: mime,
      updatedAt: 1,
      segments: const [RecordingSegment(10000, 10000), RecordingSegment(25000, 20000)],
      trimStartMs: trimStart,
      trimEndMs: trimEnd,
    );

void main() {
  group('trimmed recording', () {
    test('kept range, length and ink positions', () {
      final whole = _lecture();
      expect((whole.trimmed, whole.lengthMs, whole.keptUntil), (false, 30000, null));
      expect(whole.inkPositionOf(12000), 2000);

      final r = _lecture(trimStart: 4000, trimEnd: 20000);
      expect((r.trimmed, r.lengthMs), (true, 16000));
      // Ink before the kept audio counts as written before the recording,
      // after it as written after it; ink in the pause plays where
      // recording resumed (10 s, kept).
      expect(r.inkPositionOf(12000), isNull);
      expect(r.inkPositionOf(15000), 5000);
      expect(r.inkPositionOf(22000), 10000);
      expect(r.inkPositionOf(36000), isNull);
      // Ink made after the kept end (wall 35 000) is never veiled.
      expect(r.keptUntil, 35000);
      expect(_lecture(trimStart: 4000).keptUntil, isNull);
    });

    test('handles keep within the audio and at least a second apart', () {
      const range = (start: 2000, end: 10000);
      expect(range.withStart(-500, 30000), (start: 0, end: 10000));
      expect(range.withStart(9800, 30000), (start: 9000, end: 10000));
      expect(range.withEnd(40000, 30000), (start: 2000, end: 30000));
      expect(range.withEnd(2100, 30000), (start: 2000, end: 3000));
      expect(range.lengthMs, 8000);
      expect(range.keepsAll(30000), isFalse);
      expect((start: 0, end: 30000).keepsAll(30000), isTrue);
      // A recording shorter than the minimum keeps all of it.
      expect((start: 0, end: 600).withEnd(100, 600), (start: 0, end: 600));
      expect((start: 0, end: 600).withStart(300, 600), (start: 0, end: 600));

      const track = TrimTrack(300, 30000);
      expect(track.xOf(15000), 150);
      expect(track.msAt(75), 7500);
      expect(track.msAt(-20), 0);
      expect(track.msAt(400), 30000);
    });
  });

  group('ADTS cut', () {
    test('keeps the whole frames overlapping the range', () {
      final bytes = adtsFrames(10); // 10 × 64 ms, 16 bytes each.
      final cut = AdtsReader.cut(bytes, 100, 300);
      // Frames 64–128 … 256–320 ms.
      expect(cut.length, 4 * 16);
      expect(AdtsReader.readAll(cut).durationMs, 256);
      expect(AdtsReader.cut(bytes, 0, 640), bytes);
      expect(AdtsReader.cut(bytes, 128, 192).length, 16);
      expect(AdtsReader.cut(bytes, 700, 900), isEmpty);
    });

    test('follows sample rate changes at joints', () {
      // 5 × 64 ms at 16 kHz, then 3 × 128 ms at 8 kHz from 320 ms.
      final joined = Uint8List.fromList([...adtsFrames(5), ...adtsFrames(3, sampleRate: 8000)]);
      final cut = AdtsReader.cut(joined, 400, 500);
      expect(cut, adtsFrames(2, sampleRate: 8000));
    });
  });

  group('stored and played', () {
    late AppServices s;
    late FakeAudio audio;
    setUp(() {
      audio = FakeAudio();
      s = AppServices.create(
        AppDatabase.inMemory(),
        clock: FakeClock()..now = 100000,
        audio: audio.backends,
      );
    });
    tearDown(() => s.dispose());

    test('trim is saved, synced strictly and reset', () {
      final saved = s.recordings.save(
        notebookId: 'n',
        parts: [RecordingPart('ab' * 32, 30000)],
        mime: Recording.adtsMime,
        title: 'Lecture',
        segments: const [RecordingSegment(10000, 30000)],
      );
      expect((saved.trimStartMs, saved.trimEndMs), (0, 30000));
      final trimmed = s.recordings.trim(saved.id, 4000, 20000)!;
      expect(trimmed.updatedAt, greaterThan(saved.updatedAt));
      final got = s.recordings.get(saved.id)!;
      expect((got.trimStartMs, got.trimEndMs, got.lengthMs), (4000, 20000, 16000));
      final record = s.recordings.dirtyRecords(10).single;
      expect((record.data!['trimStartMs'], record.data!['trimEndMs']), (4000, 20000));

      s.recordings.trim(saved.id, 0, 30000);
      expect(s.recordings.get(saved.id)!.trimmed, isFalse);
    });

    test('playback keeps to the kept range', () async {
      final playback = PlaybackController(
        backends: audio.backends,
        blobs: s.blobs,
        fetch: (_) async => false,
      );
      addTearDown(playback.dispose);
      await playback.open(_lecture(trimStart: 4000, trimEnd: 20000));
      expect(audio.log, ['open Lecture', 'seek 4000', 'play']);
      expect((playback.positionMs, playback.startMs, playback.endMs), (4000, 4000, 20000));

      await playback.seek(1000);
      expect(audio.log.last, 'seek 4000');
      await playback.seek(25000);
      expect(audio.log.last, 'seek 20000');
      // Reaching the kept end stops, as the end of the recording would.
      await playback.seek(10000);
      audio.player.emit(20100);
      expect((playback.playing, playback.positionMs), (false, 20000));
      expect(audio.log.last, 'pause');
      // Playing again starts from the kept start.
      await playback.play();
      expect(audio.log.sublist(audio.log.length - 2), ['seek 4000', 'play']);
      // Ink outside the kept audio is not jumped to.
      expect(await playback.seekToInk(12000), isFalse);
      expect(await playback.seekToInk(26000), isTrue);
      expect(audio.log.sublist(audio.log.length - 1), ['seek ${11000 - 1500}']);
      // Ink made after the kept end shows; the veil stops there.
      expect(playback.veilUntil, 35000);

      // Editing the trim: the preview keeps to the draft.
      playback.beginTrim();
      expect(playback.trimDraft, (start: 4000, end: 20000));
      playback.setTrimDraft((start: 12000, end: 30000));
      expect(playback.startMs, 12000);
      expect(audio.log.last, 'seek 12000');
      expect(playback.veilUntil, isNull);
      playback.endTrim();
      expect(playback.trimDraft, isNull);
      expect((playback.startMs, playback.endMs), (4000, 20000));
    });

    test('export cuts raw AAC to the trim, other formats stay whole', () {
      expect(exportsTrimmed(_lecture(trimStart: 1000)), isTrue);
      expect(exportsTrimmed(_lecture(trimStart: 1000, mime: 'audio/webm')), isFalse);
      expect(exportsTrimmed(_lecture()), isFalse);
    });
  });
}
