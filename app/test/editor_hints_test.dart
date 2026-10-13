import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/editor/canvas/canvas_empty_hint.dart';
import 'package:len/features/editor/chrome/editor_tips.dart';
import 'package:len/features/editor/chrome/peeking.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/toolbar/tool_switcher.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ui/app_theme.dart';

import 'content_tools_ui_test.dart' show liveStrokes, mouseDrag, openCanvas, seedStroke;
import 'document_editor_test.dart' show closeEditor, drawAt, pumpEditor;
import 'editor_chrome_test.dart' show fingerTap;

double _opacityOf(WidgetTester tester, Finder finder) => tester
    .widget<AnimatedOpacity>(find.descendant(of: finder, matching: find.byType(AnimatedOpacity)))
    .opacity;

/// A short stroke drawn with a pen.
Future<void> penStroke(WidgetTester tester, Offset start) async {
  final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await pen.moveTo(start + Offset(i * 8.0, i * 2.0));
  }
  await pen.up();
  await tester.pump();
}

void main() {
  testWidgets('phones: the page indicator peeks in while pages move, then fades', (tester) async {
    final (s, _) = await pumpEditor(tester, size: const Size(390, 844));
    s.preferences.stylusOnly = true; // Fingers scroll.
    final peek = find.byType(Peeking);
    expect(find.text('1 / 3'), findsOneWidget);
    // Shown when the notebook opens…
    expect(_opacityOf(tester, peek), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    // …then out of the way (and out of the way of touches).
    expect(_opacityOf(tester, peek), 0);
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(of: find.text('1 / 3'), matching: find.byType(IgnorePointer)),
          )
          .any((w) => w.ignoring),
      isTrue,
    );
    // Scrolling brings it back.
    await tester.fling(find.byType(EditorScreen), const Offset(0, -300), 800);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, peek), 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('wide screens also peek the page indicator on scroll', (tester) async {
    await pumpEditor(tester, size: const Size(1280, 900));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, find.byType(Peeking)), 0);
    await tester.sendEventToBinding(
      const PointerScrollEvent(position: Offset(640, 450), scrollDelta: Offset(0, 500)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(_opacityOf(tester, find.byType(Peeking)), 1);
    await closeEditor(tester);
  });

  testWidgets('a pen shows the side-button tip once', (tester) async {
    final (s, _) = await pumpEditor(tester);
    s.preferences.stylusOnly = true; // Decided: no "stylus detected" snack bar.
    await penStroke(tester, const Offset(300, 400));
    await tester.pumpAndSettle();
    expect(find.text('Hold the pen’s side button to erase'), findsOneWidget);
    expect(s.settings.seenTips, contains(EditorTip.penButton.name));
    await tester.tap(find.byTooltip('Dismiss tip'));
    await tester.pumpAndSettle();
    expect(find.text('Hold the pen’s side button to erase'), findsNothing);
    expect(find.byTooltip('Dismiss tip'), findsNothing, reason: 'no multi-finger tip');
    await closeEditor(tester);
  });

  testWidgets('the side-button tip waits for the stylus-detected message', (tester) async {
    final (s, _) = await pumpEditor(tester);
    await penStroke(tester, const Offset(300, 400));
    await tester.pumpAndSettle();
    expect(find.text('Stylus detected: fingers now pan and zoom'), findsOneWidget);
    expect(find.text('Hold the pen’s side button to erase'), findsNothing);
    ScaffoldMessenger.of(tester.element(find.byType(SnackBar))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('Hold the pen’s side button to erase'), findsOneWidget);
    expect(s.settings.seenTips, contains(EditorTip.penButton.name));
    await closeEditor(tester);
  });

  testWidgets('tips follow the settings and go away by themselves', (tester) async {
    final (s, _) = await pumpEditor(tester);
    s.preferences.penButtonAction = PenButtonAction.none;
    s.preferences.stylusOnly = true;
    await penStroke(tester, const Offset(300, 500)); // Side button off: no tip for it.
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dismiss tip'), findsNothing);
    expect(s.settings.seenTips, isNot(contains('penButton')));
    await closeEditor(tester);

    final (s2, _) = await pumpEditor(tester);
    s2.preferences
      ..penButtonAction = PenButtonAction.lasso
      ..stylusOnly = true;
    await penStroke(tester, const Offset(300, 600));
    await tester.pumpAndSettle();
    expect(find.text('Hold the pen’s side button to select with the lasso'), findsOneWidget);
    await tester.pump(TipsController.visibleFor);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dismiss tip'), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('repeated two-finger undos count up in the HUD', (tester) async {
    final (s, _) = await pumpEditor(tester);
    s.settings.stylusOnly = true;
    await drawAt(tester, const Offset(300, 400));
    await drawAt(tester, const Offset(300, 500));
    await fingerTap(tester, 2);
    expect(find.text('Undo'), findsOneWidget);
    await fingerTap(tester, 2);
    expect(find.text('×2'), findsOneWidget);
    await fingerTap(tester, 2);
    expect(find.text('Nothing to undo'), findsOneWidget);
    expect(find.textContaining('×'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await closeEditor(tester);
  });

  testWidgets('an empty canvas says how to start; the first stroke hides it', (tester) async {
    final (s, nb) = await openCanvas(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final hint = find.byType(CanvasEmptyHint);
    expect(find.text('Draw anywhere'), findsOneWidget);
    expect(_opacityOf(tester, hint), 1);
    await mouseDrag(tester, const [Offset(300, 300), Offset(340, 320), Offset(380, 330)]);
    await tester.pumpAndSettle();
    expect(liveStrokes(s, nb.id), isNotEmpty);
    expect(_opacityOf(tester, hint), 0);
  });

  testWidgets('the empty-canvas hint speaks mouse with a pointer, touch on touch', (tester) async {
    Targets.debugTouchFirst = false;
    addTearDown(() => Targets.debugTouchFirst = null);
    await openCanvas(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Right-click'), findsOneWidget);
    expect(find.textContaining('Two fingers'), findsNothing);
  });

  testWidgets('a canvas with content shows no hint', (tester) async {
    await openCanvas(tester, seed: (s, nb) => s.strokes.save([seedStroke(nb.id)]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacityOf(tester, find.byType(CanvasEmptyHint)), 0);
  });

  testWidgets('the keyboard returns to the editor after menus and the tool switcher', (
    tester,
  ) async {
    await pumpEditor(tester, size: const Size(390, 844));
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    // The ⋯ menu, closed with Escape.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.escape);
    await press(LogicalKeyboardKey.keyE);
    expect(_activeTool(tester), EditorTool.eraser);

    // The phone tool switcher, closed by picking a tool.
    expect(find.byTooltip('Eraser: tap to switch tools'), findsOneWidget);
    await tester.tap(find.byType(ToolSwitcherButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlighter'));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.keyP);
    expect(_activeTool(tester), EditorTool.pen);
    await closeEditor(tester);
  });
  testWidgets('a few taps on ↶ on a touch device teach the undo gesture, once', (tester) async {
    final (s, _) = await pumpEditor(tester);
    const tip = 'Tap with two fingers to undo, three to redo';
    Future<void> undoThrice() async {
      for (var i = 0; i < 3; i++) {
        await drawAt(tester, Offset(300, 400 + i * 40.0));
      }
      for (var i = 0; i < 3; i++) {
        expect(find.text(tip), findsNothing);
        await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await undoThrice();
    expect(find.text(tip), findsOneWidget);
    expect(s.settings.seenTips, contains(EditorTip.gestureUndo.name));
    await tester.tap(find.byTooltip('Dismiss tip'));
    await tester.pumpAndSettle();
    await undoThrice();
    expect(find.text(tip), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('no undo gesture tip with a pointer or with the gesture off', (tester) async {
    Future<void> check({bool touch = true, bool gesture = true}) async {
      Targets.debugTouchFirst = touch;
      addTearDown(() => Targets.debugTouchFirst = null);
      final (s, _) = await pumpEditor(tester);
      s.preferences.fingerTapUndo = gesture;
      for (var i = 0; i < 4; i++) {
        await drawAt(tester, Offset(300, 400 + i * 40.0));
      }
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss tip'), findsNothing);
      await closeEditor(tester);
    }

    await check(touch: false);
    await check(gesture: false);
  });
}

EditorTool? _activeTool(WidgetTester tester) {
  final label = tester
      .widget<Tooltip>(
        find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').endsWith('switch tools')),
      )
      .message!;
  return {
    'Pen': EditorTool.pen,
    'Eraser': EditorTool.eraser,
    'Highlighter': EditorTool.highlighter,
  }[label.split(':').first];
}
