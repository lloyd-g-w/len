import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/versions/work_slices.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/history/version_ink_images.dart';

/// [n] short strokes of ink in rows across a 1000 × 1000 area.
List<Stroke> _ink(int n, {String id = 's'}) => [
  for (var i = 0; i < n; i++)
    Stroke(
      id: '$id$i',
      surfaceId: 'c',
      tool: InkTool.ballpoint,
      color: 0xFF1F2937,
      width: 4,
      points: [
        for (var j = 0; j < 8; j++)
          StrokePoint(10.0 + (i % 40) * 24 + j * 2, 10.0 + (i ~/ 40) * 20 + (j % 2) * 3, 0.5),
      ],
      createdAt: i,
    ),
];

InkImageKey _key(List<Stroke> strokes, {int width = 48}) =>
    (strokes: strokes, frame: const Rect.fromLTWH(0, 0, 1000, 1000), width: width, height: width);

Future<int> _inkedPixels(ui.Image image) async {
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  var inked = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    if (bytes[i] > 0) inked++;
  }
  return inked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders ink at the size asked, in turns, and hands out own handles', () async {
    final images = VersionInkImages(WorkSlices());
    addTearDown(images.dispose);
    final key = _key(_ink(1200));
    final a = (await images.image(key, wanted: () => true))!;
    expect((a.width, a.height), (48, 48));
    expect(await _inkedPixels(a), greaterThan(48 * 48 ~/ 4));
    final b = (await images.image(key, wanted: () => true))!;
    expect(b.isCloneOf(a), isTrue, reason: 'kept, not rendered again');
    a.dispose();
    expect(await _inkedPixels(b), greaterThan(0), reason: 'the other handle lives on');
    b.dispose();
    expect(images.bytes, 48 * 48 * 4);
  });

  test('keeps the most recently used images, disposing those it drops', () async {
    final images = VersionInkImages(WorkSlices(), maxCount: 2);
    addTearDown(images.dispose);
    final keys = [for (var i = 0; i < 3; i++) _key(_ink(10, id: 'k$i'))];
    for (final k in keys) {
      (await images.image(k, wanted: () => true))!.dispose();
    }
    expect(images.bytes, 2 * 48 * 48 * 4);
    final again = (await images.image(keys.first, wanted: () => true))!;
    final kept = (await images.image(keys.first, wanted: () => true))!;
    expect(kept.isCloneOf(again), isTrue);
    again.dispose();
    kept.dispose();

    final small = VersionInkImages(WorkSlices(), maxBytes: 48 * 48 * 4);
    addTearDown(small.dispose);
    for (final k in keys) {
      (await small.image(k, wanted: () => true))!.dispose();
    }
    expect(small.bytes, 48 * 48 * 4);
  });

  test('gives up what nobody wants any more, and everything when disposed', () async {
    final images = VersionInkImages(WorkSlices());
    expect(await images.image(_key(_ink(100)), wanted: () => false), isNull);
    expect(images.bytes, 0);
    final key = _key(_ink(100, id: 'w'));
    final wanted = (await images.image(key, wanted: () => true))!;
    wanted.dispose();
    final running = images.image(_key(_ink(3000, id: 'r')), wanted: () => true);
    images.dispose();
    expect(await running, isNull);
    expect(images.bytes, 0);
  });
}
