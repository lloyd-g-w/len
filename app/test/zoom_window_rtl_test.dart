import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_preferences.dart';
import 'package:len/features/editor/zoom/zoom_frame.dart';
import 'package:len/features/editor/zoom/zoom_window.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'document_editor_test.dart' show pumpEditor, inkOf, closeEditor;
import 'support/zoom_fixtures.dart';

/// A short stylus stroke in the box's paper from [at] (a fraction of its
/// size, from the bottom left) [length] pixels to the left.
Future<void> writeLeftwards(WidgetTester tester, Offset at, {double length = 40}) async {
  final paper = boxPaper(tester);
  final start = Offset(paper.left + paper.width * at.dx, paper.bottom - paper.height * at.dy);
  final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await pen.moveTo(start - Offset(length * i / 8, i.isEven ? 6 : -6));
  }
  await pen.up();
  await tester.pump();
}

/// Opens the zoom window writing right to left.
Future<ZoomWindow> openRtl(WidgetTester tester) async {
  zoomSession(tester).services.preferences.zoomRightToLeft = true;
  return openZoom(tester);
}

void main() {
  group('the direction setting', () {
    test('follows the device language until chosen', () {
      expect(AppPreferences.localeRightToLeft(const Locale('he', 'IL')), isTrue);
      expect(AppPreferences.localeRightToLeft(const Locale('ar')), isTrue);
      expect(AppPreferences.localeRightToLeft(const Locale('fa')), isTrue);
      expect(AppPreferences.localeRightToLeft(const Locale('en', 'GB')), isFalse);
      expect(AppPreferences.localeRightToLeft(const Locale('de')), isFalse);
    });

    testWidgets('a Hebrew device writes right to left; toggling twice follows it again', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = const Locale('he', 'IL');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final (s, _) = await pumpEditor(tester);
      final prefs = s.preferences;
      expect(prefs.zoomRightToLeft, isNull);
      expect(prefs.zoomWritesRightToLeft, isTrue);
      prefs.toggleZoomRightToLeft();
      expect(prefs.zoomRightToLeft, isFalse);
      expect(prefs.zoomWritesRightToLeft, isFalse);
      prefs.toggleZoomRightToLeft();
      expect(prefs.zoomRightToLeft, isNull);
      expect(prefs.zoomWritesRightToLeft, isTrue);
      final zoom = await openZoom(tester);
      expect(zoom.rightToLeft, isTrue);
      await closeEditor(tester);
    });
  });

  testWidgets('right to left, lines start at the ink\'s right', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    final zoom = await openRtl(tester);
    expect(zoom.rightToLeft, isTrue);
    final page = s.pages.pagesOf(nb.id).first;
    final wave = inkOf(s, page).single.bounds;
    final frame = zoom.frameRect!;
    expect(frame.top, greaterThan(wave.bottom));
    expect(frame.right, closeTo(wave.right, 1));
    expect(zoom.lineStart, closeTo(frame.right, 0.01));
    expect(zoom.lineEnd, zoom.host.boundsOf(page.id)!.left);
    await closeEditor(tester);
  });

  testWidgets('ink at the left edge advances the frame leftwards; ↵ goes back to the right', (
    tester,
  ) async {
    await pumpEditor(tester);
    final zoom = await openRtl(tester);
    final before = zoom.frame!.origin;
    final scale = zoom.frame!.scale;
    final pitch = zoom.host.pitchOf(zoom.frame!.surfaceId)!;
    await writeLeftwards(tester, const Offset(0.12, 0.5), length: 40);
    await tester.pumpAndSettle();
    final after = zoom.frame!.origin;
    expect(after.dy, before.dy);
    expect(after.dx, lessThan(before.dx));
    // The last ink now sits a quarter into the frame from its right.
    final rect = zoom.frameRect!;
    final inkLeft = before.dx + (0.12 * zoom.box.width - 40) / scale;
    expect(rect.right - inkLeft, closeTo(rect.width * ZoomRules.keep, rect.width * 0.05));

    await tester.tap(find.byTooltip('Next line'));
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin.dx, closeTo(before.dx, 0.01));
    expect(zoom.frame!.origin.dy, closeTo(before.dy + pitch, 0.01));
    await closeEditor(tester);
  });

  testWidgets('ink at the right of the frame does not advance it', (tester) async {
    await pumpEditor(tester);
    final zoom = await openRtl(tester);
    final before = zoom.frame!.origin;
    await writeLeftwards(tester, const Offset(0.95, 0.5), length: 20);
    await tester.pump(ZoomWindow.pause * 2);
    await tester.pumpAndSettle();
    expect(zoom.frame!.origin, before);
    await closeEditor(tester);
  });

  testWidgets('the box\'s menu turns the direction over from where the frame is', (tester) async {
    final (s, _) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    expect(zoom.rightToLeft, isFalse);
    final rect = zoom.frameRect!;
    await tester.tap(find.byTooltip('Zoom window options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right to left'));
    await tester.pumpAndSettle();
    expect(s.preferences.zoomWritesRightToLeft, isTrue);
    expect(zoom.rightToLeft, isTrue);
    expect(zoom.frameRect, rect);
    expect(zoom.lineStart, closeTo(rect.right, 0.01));
    await closeEditor(tester);
  });

  testWidgets('right to left, the size handle sits at the bottom-left and keeps the top-right', (
    tester,
  ) async {
    await pumpEditor(tester);
    final zoom = await openRtl(tester);
    final id = zoom.frame!.surfaceId;
    final screen = zoom.host.onScreen(id, zoom.frameRect!)!;
    final before = zoom.frameRect!;
    await tester.dragFrom(screen.bottomLeft, Offset(-screen.width * 0.3, screen.height * 0.3));
    await tester.pumpAndSettle();
    final after = zoom.frameRect!;
    expect(after.width, greaterThan(before.width * 1.1));
    expect(after.right, closeTo(before.right, 0.5));
    expect(after.top, closeTo(before.top, 0.5));
    await closeEditor(tester);
  });
  testWidgets('right to left, ↵ points back to the right', (tester) async {
    await pumpEditor(tester);
    final zoom = await openZoom(tester);
    double across() => tester
        .renderObject<RenderBox>(find.byIcon(Symbols.keyboard_return_sharp))
        .getTransformTo(null)
        .entry(0, 0);
    expect(across(), greaterThan(0));
    zoomSession(tester).services.preferences.zoomRightToLeft = true;
    await tester.pumpAndSettle();
    expect(zoom.rightToLeft, isTrue);
    expect(across(), lessThan(0), reason: 'mirrored');
    await closeEditor(tester);
  });

  testWidgets('the direction set elsewhere (the other pane\'s box) turns this box over too', (
    tester,
  ) async {
    final (s, _) = await pumpEditor(tester);
    final zoom = await openZoom(tester);
    final rect = zoom.frameRect!;
    s.preferences.toggleZoomRightToLeft();
    await tester.pump();
    expect(zoom.rightToLeft, isTrue);
    expect(zoom.lineStart, closeTo(rect.right, 0.01));
    await closeEditor(tester);
  });

  testWidgets('right to left, a narrower box keeps the frame\'s right edge (the line\'s start)', (
    tester,
  ) async {
    await pumpEditor(tester);
    final zoom = await openRtl(tester);
    final before = zoom.frameRect!;
    zoom.setBox(Size(zoom.box.width - 120, zoom.box.height));
    final after = zoom.frameRect!;
    expect(after.width, lessThan(before.width));
    expect(after.right, closeTo(before.right, 0.5));
    expect(after.top, before.top);
    await closeEditor(tester);
  });
}
