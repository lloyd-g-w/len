@Tags(['screenshots'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/features/documents/scan/scan_screen.dart';
import 'package:len/features/documents/scan/scan_session.dart';
import 'package:len/features/documents/scan/scan_sources.dart';
import 'package:len/features/library/library_screen.dart';

import '../support/real_async.dart';
import 'screenshot_harness.dart';

/// A photo of a handwritten page in perspective on a wooden desk, its light
/// falling off towards one corner.
Uint8List _photo(int seed) {
  const w = 900, h = 1200;
  final rnd = math.Random(seed);
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final grain = (math.sin(y / 9 + math.sin(x / 140) * 3) * 10).round();
      image.setPixelRgb(x, y, 118 + grain, 84 + grain, 58 + grain);
    }
  }
  final corners = [
    img.Point(170 + seed * 12, 150),
    img.Point(760, 190 - seed * 10),
    img.Point(800, 1060),
    img.Point(110, 1010 + seed * 8),
  ];
  img.fillPolygon(image, vertices: corners, color: img.ColorRgb8(238, 234, 222));
  // Lines of "handwriting": short wavy strokes along the page.
  img.Point at(double u, double v) {
    final top = _lerp(corners[0], corners[1], u), bottom = _lerp(corners[3], corners[2], u);
    return _lerp(top, bottom, v);
  }

  for (var line = 0; line < 14; line++) {
    final v = 0.12 + line * 0.055;
    var u = 0.1;
    final end = 0.55 + rnd.nextDouble() * 0.35;
    while (u < end) {
      final word = 0.04 + rnd.nextDouble() * 0.08;
      for (var t = 0.0; t < word; t += 0.002) {
        final p = at(u + t, v + math.sin((u + t) * 260) * 0.006);
        img.fillCircle(
          image,
          x: p.x.round(),
          y: p.y.round(),
          radius: 2,
          color: line == 0 ? img.ColorRgb8(150, 30, 40) : img.ColorRgb8(30, 40, 90),
        );
      }
      u += word + 0.025;
    }
  }
  // Uneven light: darker towards the bottom right.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final shade = 1 - 0.28 * (x / w) * (y / h);
      final p = image.getPixel(x, y);
      image.setPixelRgb(x, y, p.r * shade, p.g * shade, p.b * shade * 0.97);
    }
  }
  return img.encodeJpg(image, quality: 90);
}

img.Point _lerp(img.Point a, img.Point b, double t) =>
    img.Point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

/// The scan screen: the corners of a photographed page, then its result,
/// on a phone and a tablet, light and dark.
void main() {
  setUpAll(loadRealFonts);
  tearDown(() => ScanSources.debugSources = null);
  late final List<Uint8List> photos;
  setUpAll(() => photos = [_photo(0), _photo(1), _photo(2)]);

  for (final (device, size, dpr) in [
    ('phone', const Size(360, 780), 2.0),
    ('tablet', const Size(1180, 820), 2.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('scan $device ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        ScanSources.debugSources = ScanSources(
          pick: () async => [
            for (final (i, bytes) in photos.indexed)
              XFile.fromData(bytes, name: 'page$i.jpg', path: '/tmp/page$i.jpg'),
          ],
        );
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        // ⊕▾ where the library has one, else the new-notebook sheet's foot.
        final menu = find.byTooltip('New');
        await tester.tap(menu.evaluate().isNotEmpty ? menu : newButton());
        await settle(tester);
        await tester.ensureVisible(find.text('Scan document…').last);
        await settle(tester);
        await tester.tap(find.text('Scan document…').last);
        await tester.pump();
        await settle(tester);
        await shoot(tester, 's_scan_start_${device}_${mode.name}');
        await tester.tap(find.text('Choose photos…'));
        await tester.pump();
        ScanSession session() => tester.widget<ScanScreen>(find.byType(ScanScreen)).session;
        await pumpUntil(
          tester,
          () =>
              session().pages.length == 3 &&
              session().pages.every((p) => p.preview != null) &&
              session().display != null,
          stable: 3,
          reason: 'three scanned pages',
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_scan_corners_${device}_${mode.name}');

        await tester.tap(find.text('Preview'));
        await tester.pump();
        await pumpUntil(tester, () => session().result != null, stable: 3, reason: 'the result');
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_scan_result_${device}_${mode.name}');

        await tester.tap(find.text('B&W'));
        await tester.pump();
        await pumpUntil(tester, () => session().result != null, stable: 3, reason: 'B&W');
        await settle(tester);
        await shoot(tester, 's_scan_result_bw_${device}_${mode.name}');
      });
    }
  }
}
