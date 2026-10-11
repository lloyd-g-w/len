import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/app_services.dart';

import '../images_ui_test.dart' show seedImage;
import 'editor_screenshot_test.dart' show pumpEditor;
import 'editor_surfaces_common.dart';
import 'screenshot_harness.dart';

// Editor surfaces with real fonts, part 2: images, lasso / text / shapes,
// context menus. Page and zoom controls, tabs and the Ink Lab are in part 3.

/// A landscape "photo": sky, sun, two mountains and a lake.
Uint8List _scene(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    final t = p.y / h;
    if (t < 0.62) {
      p
        ..r = (120 + 100 * t).round()
        ..g = (170 + 60 * t).round()
        ..b = 235;
    } else {
      p
        ..r = 60
        ..g = (110 + 40 * (t - 0.6)).round()
        ..b = 160;
    }
  }
  img.fillCircle(
    image,
    x: w * 3 ~/ 4,
    y: h ~/ 4,
    radius: h ~/ 9,
    color: img.ColorRgb8(255, 210, 90),
  );
  for (final (cx, peak, color) in [
    (w * 0.3, h * 0.22, img.ColorRgb8(70, 90, 110)),
    (w * 0.62, h * 0.34, img.ColorRgb8(90, 120, 100)),
  ]) {
    img.fillPolygon(
      image,
      vertices: [
        img.Point(cx - w * 0.32, h * 0.62),
        img.Point(cx, peak),
        img.Point(cx + w * 0.32, h * 0.62),
      ],
      color: color,
    );
  }
  return img.encodeJpg(image, quality: 90);
}

/// The whiteboard with a photo to its right, under the ink.
Future<AppServices> _withPhoto(WidgetTester tester, Screen screen, ThemeMode mode) async {
  final s = bareServices();
  final board = whiteboard(s);
  await tester.runAsync(
    () => seedImage(
      s,
      board.id,
      _scene(480, 320),
      id: 'photo',
      rect: const Rect.fromLTWH(-160, 160, 330, 220),
    ),
  );
  await pumpNotebook(tester, s, board, screen: screen, mode: mode);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await settle(tester);
  return s;
}

/// A tap of the lasso tool at world [at] (selects what is there).
Future<void> _lassoTap(WidgetTester tester, Offset at) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.pump();
  await mouseDrag(tester, [canvasToScreen(tester, at)]);
  await settle(tester);
}

Future<void> _longPress(WidgetTester tester, Offset at) async {
  final finger = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 700));
  await finger.up();
  await settle(tester);
}

Future<void> _rightClick(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await settle(tester);
}

void main() {
  setUpAll(loadRealFonts);

  // 4. Images.
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_image $shot', (tester) async {
        await guardOverflows('e_image_$shot', () async {
          await _withPhoto(tester, screen, mode);
          await shoot(tester, 'e_image_canvas_$shot');
          await _lassoTap(tester, const Offset(100, 330));
          expect(find.byTooltip('Crop'), findsOneWidget);
          await shoot(tester, 'e_image_selected_$shot');
          await tester.tap(find.byTooltip('Crop'));
          await settle(tester);
          final left = canvasToScreen(tester, const Offset(-160, 270));
          await mouseDrag(tester, [left, left + const Offset(30, 0), left + const Offset(60, 0)]);
          await settle(tester);
          await shoot(tester, 'e_image_crop_$shot');
          // Closing the editor while cropping throws (setState in dispose;
          // see the report): finish the crop first.
          await tester.tap(find.text('Done'));
          await settle(tester);
        });
      });
    }
  }

  for (final mode in modes) {
    testWidgets('e_image_insert_menu ${mode.name} (Android)', (tester) async {
      await guardOverflows('e_image_insert_menu_${mode.name}', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final s = bareServices();
          await pumpNotebook(tester, s, whiteboard(s), screen: tabletScreen, mode: mode);
          await tester.tap(find.byTooltip('Insert image'));
          await settle(tester);
          expect(find.text('Take photo'), findsOneWidget);
          await shoot(tester, 'e_image_insert_menu_tablet_${mode.name}');
          await tester.tapAt(const Offset(640, 600));
          await settle(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });
  }

  // 5. Text box and shapes (the lasso menu is in part 1).
  for (final screen in [phoneScreen, tabletScreen]) {
    for (final mode in modes) {
      final shot = '${screen.name}_${mode.name}';
      testWidgets('e_text_shapes $shot', (tester) async {
        await guardOverflows('e_text_shapes_$shot', () async {
          final s = bareServices();
          await pumpNotebook(tester, s, whiteboard(s), screen: screen, mode: mode);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
          await tester.pump();
          await mouseDrag(tester, [canvasToScreen(tester, const Offset(-150, 190))]);
          await settle(tester);
          final field = find.byKey(const ValueKey('text-box-field'));
          await tester.enterText(field, 'Exam on Friday!\nRevise chapters 3–5');
          await settle(tester);
          await shoot(tester, 'e_text_editing_$shot');
          await tester.tap(find.byTooltip('Colour'));
          await settle(tester);
          await shoot(tester, 'e_text_colour_$shot');
          // Esc closes the colours, then finishes the text box (its Done
          // button is cut off on phones; see the report).
          for (var i = 0; i < 2; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await settle(tester);
          }

          // A rectangle around the heading and an ellipse.
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
          await tester.pump();
          final a = canvasToScreen(tester, const Offset(-175, -125));
          final b = canvasToScreen(tester, const Offset(195, -55));
          await mouseDrag(tester, [a, Offset.lerp(a, b, 0.5)!, b]);
          await settle(tester);
          if (screen != phoneScreen) {
            await tester.tap(find.byTooltip('Shapes (S)'));
            await settle(tester);
            await shoot(tester, 'e_shape_picker_$shot');
            await tester.tap(find.byKey(const ValueKey('shape-ellipse')));
            await settle(tester);
            final c = canvasToScreen(tester, const Offset(220, 0));
            await mouseDrag(tester, [c, c + const Offset(60, 40), c + const Offset(120, 90)]);
            await settle(tester);
          }
          await shoot(tester, 'e_shapes_$shot');
          await lassoCanvas(tester, const Rect.fromLTRB(-190, -140, 210, -40));
          await shoot(tester, 'e_shape_selected_$shot');
        });
      });
    }
  }

  // 6. Context menus.
  for (final mode in modes) {
    final m = mode.name;
    testWidgets('e_context_menu phone paged $m', (tester) async {
      await guardOverflows('e_context_menu_phone_paged_$m', () async {
        await pumpEditor(
          tester,
          size: phone,
          dpr: 2,
          mode: mode,
          phoneInsets: true,
          before: (s) => s.preferences.stylusOnly = true,
        );
        await _longPress(tester, const Offset(200, 480));
        await shoot(tester, 'e_context_menu_phone_paged_$m');
      });
    });

    testWidgets('e_context_menu canvas $m', (tester) async {
      await guardOverflows('e_context_menu_canvas_$m', () async {
        final s = bareServices()..preferences.stylusOnly = true;
        await pumpNotebook(tester, s, whiteboard(s), screen: phoneScreen, mode: mode);
        await _longPress(tester, const Offset(200, 560));
        await shoot(tester, 'e_context_menu_phone_canvas_$m');
      });
    });

    testWidgets('e_context_menu desktop canvas $m', (tester) async {
      await guardOverflows('e_context_menu_desktop_canvas_$m', () async {
        final s = bareServices();
        await pumpNotebook(tester, s, whiteboard(s), screen: desktopScreen, mode: mode);
        await _rightClick(tester, const Offset(1100, 300));
        await shoot(tester, 'e_context_menu_desktop_canvas_$m');
      });
    });
  }
}
