import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';

import 'screenshot_harness.dart';

const phone = Size(390, 844);
const narrowPhone = Size(320, 640);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);
const desktop = Size(1440, 900);

/// Opens the seeded "Physics" notebook (three pages of handwriting) and,
/// with [tabs], two more notebooks in tabs; [canvas] shows the whiteboard.
Future<AppServices> pumpEditor(
  WidgetTester tester, {
  required Size size,
  double dpr = 1,
  ThemeMode mode = ThemeMode.light,
  bool canvas = false,
  bool tabs = false,
  bool phoneInsets = false,
  void Function(AppServices s)? before,
}) async {
  setWindow(tester, size, dpr: dpr);
  if (phoneInsets) {
    tester.view.padding = FakeViewPadding(top: 28 * dpr, bottom: 20 * dpr);
    addTearDown(tester.view.resetPadding);
  }
  final s = seededServices();
  addTearDown(s.dispose);
  final notebooks = s.notebooks.list();
  Notebook named(String prefix) => notebooks.firstWhere((n) => n.title.startsWith(prefix));
  final physics = named('Physics');
  final first = s.pages.pagesOf(physics.id).first;
  for (var i = 0; i < 2; i++) {
    final page = s.pages.addPage(physics.id, paper: PaperStyle.wideRuled);
    s.strokes.save([
      for (final st in SurfaceCopier(s.strokes).loadAll(first.id).take(20 + i * 10))
        Stroke(
          id: '${st.id}-$i',
          surfaceId: page.id,
          tool: st.tool,
          color: st.color,
          width: st.width,
          points: st.points,
          createdAt: st.createdAt,
        ),
    ]);
  }
  if (tabs) {
    s.openNotebooks
      ..open(named('Meeting'))
      ..open(named('Whiteboard'));
  }
  s.openNotebooks.open(canvas ? named('Whiteboard') : physics);
  before?.call(s);
  await pumpApp(tester, s, const EditorWorkspace(), mode: mode);
  expect(tester.takeException(), isNull);
  return s;
}

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr, insets) in [
    ('tablet', tablet, 1.0, false),
    ('tablet_portrait', tabletPortrait, 1.0, false),
    ('phone', phone, 2.0, true),
    ('desktop', desktop, 1.0, false),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final canvas in [false, true]) {
        final kind = canvas ? 'canvas' : 'paged';
        testWidgets('editor $name $kind ${mode.name}', (tester) async {
          await pumpEditor(
            tester,
            size: size,
            dpr: dpr,
            mode: mode,
            canvas: canvas,
            tabs: !canvas,
            phoneInsets: insets,
          );
          await shoot(tester, 'editor_${name}_${kind}_${mode.name}');
        });
      }
    }
  }

  testWidgets('editor 320 dp phone has no overflow', (tester) async {
    await pumpEditor(tester, size: narrowPhone, dpr: 2, tabs: true, phoneInsets: true);
    await shoot(tester, 'editor_narrow_paged');
  });

  testWidgets('editor single-page flow (tablet portrait)', (tester) async {
    await pumpEditor(tester, size: tabletPortrait, before: (s) => s.settings.pageFlow = 'single');
    await tester.tap(find.byTooltip('Next page'));
    await settle(tester);
    await shoot(tester, 'editor_single_page');
  });

  testWidgets('editor focus mode', (tester) async {
    await pumpEditor(tester, size: tablet);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await settle(tester);
    await shoot(tester, 'editor_focus');
    await tester.tap(find.byTooltip('Show toolbars (F11)'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  for (final placement in [ToolbarPlacement.bottom, ToolbarPlacement.floating]) {
    testWidgets('editor toolbar ${placement.name}', (tester) async {
      await pumpEditor(
        tester,
        size: tablet,
        before: (s) => s.preferences.toolbarPlacement = placement,
      );
      await shoot(tester, 'editor_toolbar_${placement.name}');
    });
  }

  testWidgets('editor menus, context menu and HUD', (tester) async {
    await pumpEditor(tester, size: tablet, tabs: true);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await shoot(tester, 'editor_more_menu');
    await tester.tapAt(const Offset(640, 600));
    await settle(tester);

    // Right click → context menu.
    await tester.tapAt(
      const Offset(500, 420),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    await shoot(tester, 'editor_context_menu');
    await tester.tapAt(const Offset(1000, 700));
    await settle(tester);

    // Two-finger tap → HUD.
    final a = await tester.startGesture(const Offset(400, 400));
    final b = await tester.startGesture(const Offset(600, 400));
    await a.up();
    await b.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await shoot(tester, 'editor_hud');
    await settle(tester);
  });

  testWidgets('editor canvas more menu', (tester) async {
    await pumpEditor(tester, size: tablet, canvas: true);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    expect(find.text('Fit content'), findsOneWidget);
    expect(find.text('Back to start'), findsOneWidget);
    await shoot(tester, 'editor_canvas_more_menu');
  });

  testWidgets('editor phone menu and tab switcher', (tester) async {
    await pumpEditor(tester, size: phone, dpr: 2, tabs: true, phoneInsets: true);
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await shoot(tester, 'editor_phone_more_menu');
    await tester.tapAt(const Offset(20, 700));
    await settle(tester);
    await tester.tap(find.byTooltip('Open notebooks'));
    await settle(tester);
    await shoot(tester, 'editor_phone_tabs');
  });

  testWidgets('editor hints: phone page indicator, tips, empty canvas', (tester) async {
    await pumpEditor(
      tester,
      size: phone,
      dpr: 2,
      phoneInsets: true,
      before: (s) => s.settings.stylusOnly = true,
    );
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    await shoot(tester, 'editor_phone_indicator_hidden');
    // A pen stroke: the side-button tip (the indicator peeks back in only
    // when pages move).
    final pen = await tester.startGesture(const Offset(120, 520), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await pen.moveTo(Offset(120 + i * 10.0, 520 + (i.isEven ? 6 : -6)));
    }
    await pen.up();
    await settle(tester);
    await shoot(tester, 'editor_phone_tip');
    await tester.tap(find.byTooltip('Dismiss tip'));
    await settle(tester);
    await shoot(tester, 'editor_phone_tip_gestures');
    await tester.pump(const Duration(seconds: 11));
    await settle(tester);
  });

  for (final (name, size, dpr) in [('phone', phone, 2.0), ('tablet', tablet, 1.0)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('editor empty canvas $name ${mode.name}', (tester) async {
        await pumpEditor(
          tester,
          size: size,
          dpr: dpr,
          mode: mode,
          before: (s) => s.openNotebooks.open(
            s.notebooks.create(
              title: 'Ideas',
              kind: NotebookKind.canvas,
              paper: PaperStyle.blank,
              coverColor: 0xFF3B5BDB,
            ),
          ),
        );
        await settle(tester);
        await shoot(tester, 'editor_empty_canvas_${name}_${mode.name}');
      });
    }
  }
}
