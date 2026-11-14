import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/ebml.dart';
import 'package:len/features/audio/mp4_cut.dart';
import 'package:len/features/audio/recording_export.dart';
import 'package:len/features/audio/webm_cut.dart';
import 'package:len/features/documents/export/export_flow.dart' show ExportFile;
import 'package:len/platform/file_export.dart';

import 'support/audio_containers.dart';

const _cluster = 0x1F43B675, _info = 0x1549A966, _tracks = 0x1654AE6B;

/// A WebM file as browsers write it: unknown sizes ([live]), a SeekHead,
/// Cues; [clusters] clusters of 1 s holding a 20-ms block every 20 ms
/// (payload: cluster, block).
Uint8List _webm({bool live = true, int clusters = 3}) => Uint8List.fromList([
  ...ebml(0x1A45DFA3, [
    Ebml.element(0x4282, [utf8.encode('webm')]),
  ]),
  ...ebml(0x18538067, unknown: live, [
    ebml(0x114D9B74, [ebml(0x4DBB, [])]),
    ebml(_info, [Ebml.uintElement(0x2AD7B1, 1000000), Ebml.floatElement(0x4489, 3000)]),
    ebml(_tracks, [
      ebml(0xAE, [
        Ebml.uintElement(0xD7, 1),
        Ebml.element(0x86, [utf8.encode('A_OPUS')]),
      ]),
    ]),
    for (var c = 0; c < clusters; c++)
      ebml(_cluster, unknown: live, [
        Ebml.uintElement(0xE7, c * 1000),
        for (var b = 0; b < 50; b++) simpleBlock(b * 20, [c, b]),
      ]),
    ebml(0x1C53BB6B, [ebml(0xBB, [])]),
  ]),
]);

/// A fragmented MP4 file: AAC frames of 1024 samples at 44.1 kHz (≈ 23.2
/// ms), [fragments] fragments of 10, sample i holding i % 3 + 1 bytes of i;
/// with [edit] an edit list skipping the first frame (AAC priming).
Uint8List _mp4({int fragments = 4, bool plain = false, bool edit = false}) {
  final moov = box('moov', [
    fullBox('mvhd', 0, 0, [0, 0, 1000, 5000]),
    box('trak', [
      fullBox('tkhd', 0, 7, [0, 0, 1, 0, 5000]),
      if (edit)
        box('edts', [
          fullBox('elst', 0, 0, [1, 5000, 1024, 0x00010000]),
        ]),
      box('mdia', [
        fullBox('mdhd', 0, 0, [0, 0, 44100, 0]),
      ]),
    ]),
    if (!plain)
      box('mvex', [
        fullBox('mehd', 0, 0, [5000]),
        fullBox('trex', 0, 0, [1, 1, 1024, 0, 0x02000000]),
      ]),
  ]);
  final out = BytesBuilder()
    ..add(box('ftyp', [Uint8List.fromList('isomiso6'.codeUnits)]))
    ..add(moov);
  for (var f = 0; f < fragments; f++) {
    final ids = [for (var i = f * 10; i < f * 10 + 10; i++) i];
    Uint8List moof(int dataOffset) => box('moof', [
      fullBox('mfhd', 0, 0, [f + 1]),
      box('traf', [
        fullBox('tfhd', 0, 0x020008, [1, 1024]),
        fullBox('tfdt', 0, 0, [f * 10 * 1024]),
        fullBox('trun', 0, 0x201, [ids.length, dataOffset, for (final i in ids) i % 3 + 1]),
      ]),
    ]);
    final size = moof(0).length;
    out
      ..add(moof(size + 8))
      ..add(
        box('mdat', [
          Uint8List.fromList([for (final i in ids) ...List.filled(i % 3 + 1, i)]),
        ]),
      );
  }
  out.add(box('mfra', []));
  return out.takeBytes();
}

Uint8List _fixture(String name) => File('test/fixtures/audio/$name').readAsBytesSync();

void main() {
  group('WebM', () {
    test('cuts to the blocks overlapping the range, rebased, in known sizes', () {
      for (final live in [true, false]) {
        final cut = WebmCut.cut(_webm(live: live), fromMs: 1010, toMs: 2050)!;
        final w = readWebm(cut);
        expect(w.times, [for (var t = 0; t <= 1040; t += 20) t], reason: 'live $live');
        expect(w.clusters, [0, 1000]);
        expect(w.payloads.first, [1, 0]);
        expect(w.payloads.last, [2, 2]);
        expect(w.duration, 1060);
        expect(w.topLevel, [_info, _tracks, _cluster, _cluster]); // No SeekHead, no Cues.
      }
    });

    test('open ends keep the start or the end', () {
      expect(readWebm(WebmCut.cut(_webm(), toMs: 30)!).times, [0, 20]);
      final tail = readWebm(WebmCut.cut(_webm(), fromMs: 2980)!);
      expect(tail.times, [0]);
      expect(tail.payloads.single, [2, 49]);
      expect(tail.duration, 20);
    });

    test('splits clusters whose offsets outgrow 16 bits; BlockGroups and their durations', () {
      final group = ebml(0xA0, [
        Ebml.element(0xA1, [
          Uint8List.fromList([0x81, 0x7D, 0x00, 0x00, 9]), // +32000
        ]),
        Ebml.uintElement(0x9B, 60),
      ]);
      final file = Uint8List.fromList([
        ...ebml(0x1A45DFA3, []),
        ...ebml(0x18538067, [
          ebml(_info, []),
          ebml(_cluster, [
            Ebml.uintElement(0xE7, 40000),
            simpleBlock(-32000, [7]),
            simpleBlock(0, [8]),
            group,
          ]),
        ]),
      ]);
      final w = readWebm(WebmCut.cut(file, fromMs: 1)!);
      expect(w.times, [0, 32000, 64000]);
      expect(w.clusters, [0, 64000]);
      expect(w.payloads, [
        [7],
        [8],
        [9],
      ]);
      expect(w.duration, 64060);
    });

    test('malformed or empty input returns null (export falls back to whole parts)', () {
      final ok = _webm(live: false);
      expect(WebmCut.cut(Uint8List(0), fromMs: 10), isNull);
      expect(WebmCut.cut(Uint8List(1000), fromMs: 10), isNull);
      expect(
        WebmCut.cut(Uint8List.fromList(List.generate(3000, (i) => i * 7)), fromMs: 10),
        isNull,
      );
      expect(WebmCut.cut(ok.sublist(0, ok.length - 10), fromMs: 10), isNull);
      expect(WebmCut.cut(ok.sublist(0, 40), fromMs: 10), isNull);
      expect(WebmCut.cut(_webm(clusters: 0), fromMs: 10), isNull);
      expect(WebmCut.cut(ok, fromMs: 5000), isNull);
      for (var n = 0; n < ok.length; n += 7) {
        final broken = Uint8List.fromList(ok)..[n] ^= 0xFF;
        WebmCut.cut(broken, fromMs: 500, toMs: 1500); // Never throws.
      }
    });
  });

  group('fragmented MP4', () {
    test('cuts to the samples overlapping the range, rebased', () {
      final cut = Mp4Cut.cut(_mp4(), fromMs: 300, toMs: 700)!;
      final m = readMp4(cut);
      // Samples 12…30 (23.2 ms each): 11 ends at 278.6 ms, 30 starts at 696.6.
      expect(m.times, [for (var i = 0; i < 19; i++) i * 1024]);
      expect(m.payloads.first, List.filled(12 % 3 + 1, 12));
      expect(m.payloads.last, List.filled(30 % 3 + 1, 30));
      expect(m.top, ['ftyp', 'moov', 'moof', 'mdat', 'moof', 'mdat', 'moof', 'mdat']);
      // Durations rewritten where set: mvhd, tkhd, mehd 441 ms; mdhd stays 0.
      final moov = boxes(cut).firstWhere((b) => b.$1 == 'moov');
      final data = ByteData.sublistView(cut);
      int word(String type, int index) {
        final at = latin1.decode(cut).indexOf(type, moov.$2);
        return data.getUint32(at + 8 + 4 * index);
      }

      expect(
        [word('mvhd', 3), word('tkhd', 4), word('mehd', 0), word('mdhd', 3)],
        [441, 441, 441, 0],
      );
    });

    test('an edit list keeps its priming skip, its duration rewritten', () {
      final cut = Mp4Cut.cut(_mp4(edit: true), fromMs: 300, toMs: 700)!;
      expect(readMp4(cut).times, hasLength(19));
      final at = latin1.decode(cut).indexOf('elst');
      final data = ByteData.sublistView(cut);
      // 19 frames less the skipped one: 18 × 1024 / 44.1 kHz = 417 ms.
      expect([data.getUint32(at + 12), data.getUint32(at + 16)], [417, 1024]);
    });

    test('malformed, plain or empty input returns null', () {
      final ok = _mp4();
      expect(Mp4Cut.cut(Uint8List(0), fromMs: 10), isNull);
      expect(Mp4Cut.cut(Uint8List(100), fromMs: 10), isNull);
      expect(Mp4Cut.cut(ok.sublist(0, ok.length - 20), fromMs: 10), isNull);
      expect(Mp4Cut.cut(_mp4(plain: true), fromMs: 10), isNull);
      expect(Mp4Cut.cut(_mp4(fragments: 0), fromMs: 10), isNull);
      expect(Mp4Cut.cut(ok, fromMs: 2000), isNull);
      for (var n = 0; n < ok.length; n += 3) {
        final broken = Uint8List.fromList(ok)..[n] ^= 0xFF;
        Mp4Cut.cut(broken, fromMs: 100, toMs: 500); // Never throws.
      }
    });
  });

  group('real files (Chromium, ffmpeg)', () {
    for (final (name, mime) in [
      ('chrome.webm', 'audio/webm'), // Chromium's MediaRecorder: 60-ms packets, a pause.
      ('opus.webm', 'audio/webm'),
      ('opus_live.webm', 'audio/webm'),
      ('aac.m4a', 'audio/mp4'),
    ]) {
      test('$name cuts to 1…2 s and still decodes', () async {
        final cut = cutAudio(mime, _fixture(name), fromMs: 1000, toMs: 2000)!;
        final times = mime == 'audio/webm' ? readWebm(cut).times : readMp4(cut).times;
        expect(times.first, 0);
        final probed = await probe(cut, name);
        if (probed == null) {
          markTestSkipped('ffmpeg not installed');
          return;
        }
        expect(probed.$1, closeTo(0, 0.01)); // Opus starts −6.5 ms: its codec delay.
        // Whole packets overlapping the range: up to one more at either end.
        expect(probed.$2, closeTo(1.0, 0.13));
      });

      test('$name: two parts join into one file that still decodes', () async {
        final file = _fixture(name);
        final one = await probe(file, name);
        if (one == null) {
          markTestSkipped('ffmpeg not installed');
          return;
        }
        final length = ((one.$2 - one.$1) * 1000).round();
        final joined = joinAudio(mime, [file, file], [0, length])!;
        final probed = (await probe(joined, name))!;
        expect(probed.$2 - probed.$1, closeTo(2 * (one.$2 - one.$1), 0.15));
        // Cut across the join.
        final cut = joinAudio(
          mime,
          [file, file],
          [0, length],
          fromMs: length - 500,
          toMs: length + 500,
        )!;
        final c = (await probe(cut, name))!;
        expect(c.$2, closeTo(1.0, 0.15));
      });
    }

    test('browser and live WebM have unknown sizes', () {
      for (final name in ['chrome.webm', 'opus_live.webm']) {
        final d = _fixture(name);
        final segment = Ebml.read(d, Ebml.read(d, 0, d.length)!.end, d.length)!;
        expect(segment.unknown, isTrue);
        var e = Ebml.read(d, segment.dataStart, d.length)!;
        while (e.id != _cluster) {
          e = Ebml.read(d, e.end, d.length)!;
        }
        expect(e.unknown, name == 'chrome.webm', reason: name);
      }
    });
  });

  group('export', () {
    Recording lecture(String mime, {int trimStart = 0, int? trimEnd}) => Recording(
      id: 'r',
      notebookId: 'n',
      parts: [for (final c in 'abc'.split('')) RecordingPart(c * 64, 300000)],
      durationMs: 900000,
      startedAt: 0,
      title: 'Lecture',
      mime: mime,
      updatedAt: 1,
      trimStartMs: trimStart,
      trimEndMs: trimEnd,
    );

    test('one file carries the parts the trim touches and the cut that keeps to it', () {
      // (the parts' blobs by their first letter, their starts, from, to)
      List<Object?> group(Recording r) {
        final g = exportGroupOf(r);
        return [g.blobs.map((b) => b[0]).join(), g.startsMs, g.fromMs, g.toMs];
      }

      expect(group(lecture('audio/webm', trimStart: 310000, trimEnd: 590000)), [
        'b',
        [0],
        10000,
        290000,
      ]);
      expect(group(lecture('audio/mp4', trimStart: 10000, trimEnd: 610000)), [
        'abc',
        [0, 300000, 600000],
        10000,
        610000,
      ]);
      expect(group(lecture('audio/webm')), [
        'abc',
        [0, 300000, 600000],
        null,
        null,
      ]);
      expect(group(lecture(Recording.adtsMime, trimStart: 310000, trimEnd: 590000)), [
        'abc',
        null,
        310000,
        590000,
      ]);
      // Should they not join: one file per part, each cut to the trim.
      List<(String, int?, int?)> parts(Recording r) => [
        for (final g in partGroupsOf(exportGroupOf(r)))
          (g.blobs.map((b) => b[0]).join(), g.fromMs, g.toMs),
      ];
      expect(parts(lecture('audio/mp4', trimStart: 10000, trimEnd: 610000)), [
        ('a', 10000, null),
        ('b', null, null),
        ('c', null, 10000),
      ]);
      expect(parts(lecture('audio/webm')), [
        ('a', null, null),
        ('b', null, null),
        ('c', null, null),
      ]);
    });

    test('parts join into one file, each from where it starts (WebM, MP4)', () {
      // Three 3-s WebM parts recorded as 3 s each: blocks every 20 ms on.
      final webm = WebmCut.join([for (var i = 0; i < 3; i++) (bytes: _webm(), startMs: 3000 * i)])!;
      final w = readWebm(webm);
      expect(w.times.length, 3 * 150);
      expect(w.times.take(3), [0, 20, 40]);
      expect(w.times.skip(150).first, 3000);
      expect(w.times.last, 8980);
      // Cut across the joins: 2.5 s … 6.5 s.
      final cut = readWebm(
        WebmCut.join(
          [for (var i = 0; i < 3; i++) (bytes: _webm(), startMs: 3000 * i)],
          fromMs: 2500,
          toMs: 6500,
        )!,
      );
      expect(cut.times.first, 0);
      expect(cut.duration, closeTo(4000, 30));
      // A part recorded longer than its audio leaves a gap; shorter never
      // overlaps.
      final overlap = readWebm(
        WebmCut.join([(bytes: _webm(), startMs: 0), (bytes: _webm(), startMs: 2000)])!,
      );
      for (var i = 1; i < overlap.times.length; i++) {
        expect(overlap.times[i], greaterThan(overlap.times[i - 1]));
      }
      // Parts with other tracks don't join.
      expect(
        WebmCut.join([(bytes: _webm(), startMs: 0), (bytes: Uint8List(10), startMs: 3000)]),
        isNull,
      );

      final mp4 = readMp4(
        Mp4Cut.join([(bytes: _mp4(), startMs: 0), (bytes: _mp4(), startMs: 1000)])!,
      );
      expect(mp4.times.length, 80);
      expect(mp4.times[40], (1000 * 44100 / 1000).round());
      final mp4Cut = readMp4(
        Mp4Cut.join(
          [(bytes: _mp4(), startMs: 0), (bytes: _mp4(), startMs: 1000)],
          fromMs: 500,
          toMs: 1500,
        )!,
      );
      expect(mp4Cut.times.first, 0);
    });

    test('cutAudio leaves uncut audio alone and gives up on what it cannot cut', () {
      final junk = Uint8List(100);
      expect(identical(cutAudio('audio/webm', junk), junk), isTrue);
      expect(cutAudio('audio/webm', junk, fromMs: 10), isNull);
      expect(cutAudio('audio/wav', junk, fromMs: 10), isNull);
    });

    testWidgets('a trimmed browser recording exports cut, without the caveat', (tester) async {
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      final bytes = _fixture('opus_live.webm');
      final sha = (await tester.runAsync(
        () => services.blobs.putFile(XFile.fromData(bytes), mime: 'audio/webm'),
      ))!;
      final r = Recording(
        id: 'r',
        notebookId: 'n',
        parts: [RecordingPart(sha, 3000)],
        durationMs: 3000,
        startedAt: 0,
        title: 'Talk',
        mime: 'audio/webm',
        updatedAt: 1,
        trimStartMs: 500,
        trimEndMs: 2500,
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      List<ExportFile>? exported;
      await tester.runAsync(
        () => exportRecordings(
          context,
          [r],
          blobs: services.blobs,
          fetch: (_) async => false,
          save: (files, {required mime, toDevice = false, subject}) async {
            exported = files;
            return ExportedFiles(ExportedTo.downloaded, count: files.length);
          },
        ),
      );
      await tester.pump();
      expect(exported!.single.name, 'Talk.webm');
      expect(exported!.single.bytes.length, lessThan(bytes.length));
      final w = readWebm(exported!.single.bytes);
      expect(w.duration, closeTo(2000, 30));
      expect(find.textContaining('may start earlier'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
