import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/recording.dart';
import 'package:len/domain/recording_release.dart';
import 'package:len/domain/waveform.dart';
import 'package:len/features/audio/playback_controller.dart';
import 'package:len/features/audio/recording_export.dart';
import 'package:len/features/audio/trim_release.dart';

import 'data_test.dart' show FakeClock;
import 'support/fake_audio.dart';

const _part = 300000; // 5 min.

/// 15 min in three parts, recorded from wall time 10 000 with a 60 s pause
/// 7 min in: audio 0…7 min = wall 10 000…, audio 7…15 min = 60 s later.
Recording _lecture({
  int trimStart = 0,
  int? trimEnd,
  String mime = 'audio/webm',
  List<String>? blobs,
}) {
  final b = blobs ?? ['aa' * 32, 'bb' * 32, 'cc' * 32];
  return Recording(
    id: 'r',
    notebookId: 'n',
    parts: [for (final sha in b) RecordingPart(sha, _part)],
    durationMs: 3 * _part,
    startedAt: 10000,
    title: 'Lecture',
    mime: mime,
    updatedAt: 1,
    segments: const [RecordingSegment(10000, 420000), RecordingSegment(490000, 480000)],
    trimStartMs: trimStart,
    trimEndMs: trimEnd,
  );
}

void main() {
  group('parts outside the trim', () {
    test('only parts wholly outside the kept audio', () {
      expect(_lecture().partsOutsideTrim, isEmpty);
      expect(_lecture(trimStart: 10000, trimEnd: 890000).partsOutsideTrim, isEmpty);
      final middle = _lecture(trimStart: 310000, trimEnd: 590000);
      expect(middle.partsTouching(310000, 590000), (first: 1, end: 2));
      expect(middle.partsOutsideTrim.map((p) => p.blob), ['aa' * 32, 'cc' * 32]);
      // A trim on the joints keeps exactly the middle part.
      expect(_lecture(trimStart: _part, trimEnd: 2 * _part).partsTouching(_part, 2 * _part), (
        first: 1,
        end: 2,
      ));
      expect(_lecture(trimEnd: 200000).partsOutsideTrim.length, 2);
      expect(_lecture(trimStart: 899000).partsOutsideTrim.length, 2);
    });

    test('dropping them moves trim, timeline and ink to the kept parts', () {
      final before = _lecture(trimStart: 310000, trimEnd: 590000);
      final after = before.withoutPartsOutsideTrim(waveform: '', updatedAt: 2);
      expect(after.parts.map((p) => p.blob), ['bb' * 32]);
      expect((after.durationMs, after.trimStartMs, after.trimEndMs), (_part, 10000, 290000));
      expect(after.lengthMs, before.lengthMs);
      // Audio 5…7 min, the pause, 7…10 min.
      expect(after.segments, const [
        RecordingSegment(310000, 120000),
        RecordingSegment(490000, 180000),
      ]);
      expect(after.startedAt, 310000);
      // Ink maps to the same moments (shifted by the dropped 5 min).
      for (final wall in [320000, 450000, 500000, 600000]) {
        expect(after.inkPositionOf(wall), before.inkPositionOf(wall)! - _part, reason: '$wall');
      }
      expect(after.inkPositionOf(100000), isNull);
      expect(after.keptUntil, before.keptUntil);
      expect(before.keptPartsRange, (fromMs: _part, toMs: 2 * _part));
      // Nothing outside: unchanged.
      final whole = _lecture(trimStart: 1000);
      expect(identical(whole.withoutPartsOutsideTrim(waveform: '', updatedAt: 2), whole), isTrue);
    });

    test('waveform slices to the nearest bucket', () {
      final w = Waveform(Uint8List.fromList(List.generate(90, (i) => i)), bucketMs: 1000);
      expect(w.slice(30040, 59960).levels, List.generate(30, (i) => 30 + i));
      expect(w.slice(0, 200000).levels.length, 90);
    });

    test('browser recordings export the parts the trim touches', () {
      final trimmed = _lecture(trimStart: 310000, trimEnd: 590000);
      expect(exportGroups(trimmed), [
        ['bb' * 32],
      ]);
      expect(exportsWider(trimmed), isTrue);
      expect(exportsWider(_lecture(trimStart: _part, trimEnd: 2 * _part)), isFalse);
      expect(exportsWider(_lecture()), isFalse);
      // Raw AAC joins and is cut exactly.
      final adts = _lecture(trimStart: 310000, trimEnd: 590000, mime: Recording.adtsMime);
      expect(exportGroups(adts).single.length, 3);
      expect(exportsWider(adts), isFalse);
    });
  });

  group('freeing the space', () {
    late FakeClock clock;
    late AppServices s;
    setUp(() {
      clock = FakeClock()..now = DateTime(2026, 10, 1).millisecondsSinceEpoch;
      s = AppServices.create(AppDatabase.inMemory(), clock: clock);
    });
    tearDown(() => s.dispose());

    Future<String> blob(int fill, int size) =>
        s.blobs.putBytes(Uint8List(size)..fillRange(0, size, fill), mime: 'audio/webm');

    test('drops the parts, syncs the shorter list, GC frees them; undo restores', () async {
      final shas = [await blob(1, 1000), await blob(2, 2000), await blob(3, 4000)];
      final waveform = await s.blobs.putBytes(
        Waveform(Uint8List.fromList(List.generate(9000, (i) => i % 256))).encode(),
        mime: Waveform.mime,
      );
      final saved = s.recordings.save(
        notebookId: 'n',
        parts: [for (final sha in shas) RecordingPart(sha, _part)],
        mime: 'audio/webm',
        title: 'Lecture',
        segments: const [RecordingSegment(10000, 3 * _part)],
        waveform: waveform,
      );
      expect(releasableBytes(saved, blobs: s.blobs, shared: {}), isNull);
      final trimmed = s.recordings.trim(saved.id, 310000, 590000)!;
      expect(releasableBytes(trimmed, blobs: s.blobs, shared: {}), 5000);
      // A blob another recording shares is not freed.
      expect(releasableBytes(trimmed, blobs: s.blobs, shared: {shas[2]}), 1000);

      final released = (await releaseOutsideTrim(
        saved.id,
        repository: s.recordings,
        blobs: s.blobs,
        fetch: (_) async => false,
      ))!;
      expect(released.before.parts.length, 3);
      final after = s.recordings.get(saved.id)!;
      expect(after.parts.map((p) => p.blob), [shas[1]]);
      expect((after.trimStartMs, after.trimEndMs), (10000, 290000));
      expect(after.updatedAt, greaterThan(trimmed.updatedAt));
      final cut = Waveform.decode((await s.blobs.read(after.waveform))!)!;
      expect(cut.levels.length, 3000);
      expect(cut.levels.first, 3000 % 256);

      // Another device takes the shorter parts list with the row.
      final record = s.recordings.dirtyRecords(10).single;
      expect(record.data!['audio'], [
        [shas[1], _part],
      ]);
      final other = AppServices.create(AppDatabase.inMemory(), clock: FakeClock());
      addTearDown(other.dispose);
      other.recordings.writeRemote(record);
      final synced = other.recordings.get(saved.id)!;
      expect(synced.parts, after.parts);
      expect((synced.trimStartMs, synced.waveform), (10000, after.waveform));

      // Undo (within the grace period) puts the parts back.
      s.recordings.replace(released.before);
      expect(s.recordings.get(saved.id)!.parts.length, 3);
      s.recordings.replace(released.after);

      // Garbage collection frees the dropped parts after its grace period.
      await s.blobGc.run();
      clock.now += const Duration(days: 8).inMilliseconds;
      final deleted = await s.blobGc.run();
      expect(deleted, containsAll([shas[0], shas[2], waveform]));
      expect(deleted, isNot(contains(shas[1])));
    });

    test('playback reopens audio whose parts changed', () async {
      final audio = FakeAudio();
      final playback = PlaybackController(
        backends: audio.backends,
        blobs: s.blobs,
        fetch: (_) async => false,
      );
      addTearDown(playback.dispose);
      final before = _lecture(trimStart: 310000, trimEnd: 590000);
      await playback.open(before, autoplay: false);
      // Its audio is not here: played part by part, from the second.
      expect(audio.log, ['open Lecture', 'seek 10000']);
      expect(audio.player.opened!.parts.single.blob, 'bb' * 32);
      playback.update(before.copyWith(title: 'Renamed'));
      expect(audio.log.length, 2);
      playback.update(before.withoutPartsOutsideTrim(waveform: '', updatedAt: 2));
      await pumpEventQueue();
      expect(audio.log.sublist(2), ['open Lecture', 'seek 10000']);
      expect(playback.positionMs, 10000);
    });
  });
}
