import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/features/editor/tools/laser_options_panel.dart';
import 'package:len/features/editor/tools/laser_overlay.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/tools/laser_tool.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

const _hold = LaserConfig(fade: LaserFade.pause);

/// A short stroke from [from], right 30 units.
void _stroke(LaserTrail trail, Offset from) {
  trail.down(from);
  for (var i = 1; i <= 3; i++) {
    trail.move(from + Offset(i * 10, 0));
  }
  trail.up();
}

void main() {
  group('held laser trail', () {
    test('stays in full until the hold has passed after the last lift, then fades together', () {
      final trail = LaserTrail()..config = _hold;
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail.tick(1000); // The lift is stamped on this frame.
      trail.tick(1000 + 1900);
      expect(trail.length, 4);
      expect([for (var i = 0; i < 4; i++) trail.alphaAt(i)], everyElement(1));
      expect(trail.headAlpha, 1);
      final fadeStart = 1000 + _hold.hold.inMilliseconds;
      trail.tick(fadeStart + LaserTrail.holdFade.inMilliseconds / 2);
      expect([for (var i = 0; i < 4; i++) trail.alphaAt(i)], everyElement(closeTo(0.5, 1e-9)));
      expect(trail.headAlpha, closeTo(0.5, 1e-9), reason: 'the dot goes with the trail');
      trail.tick(fadeStart + LaserTrail.holdFade.inMilliseconds + 0.0);
      expect(trail.isEmpty, isTrue);
      expect(trail.isVisible, isFalse);
      expect(trail.animating, isFalse);
    });

    test('a press within the hold keeps everything; the countdown restarts at the next lift', () {
      final trail = LaserTrail()..config = _hold;
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail
        ..tick(0)
        ..tick(1500);
      // Writing again, for longer than the hold.
      trail.down(const Offset(0, 20));
      expect(trail.animating, isFalse, reason: 'nothing changes while held');
      trail
        ..move(const Offset(10, 20))
        ..tick(1600)
        ..tick(5000);
      expect(trail.length, 6);
      expect(trail.alphaAt(0), 1, reason: 'the first stroke is still in full');
      trail.up();
      expect(trail.animating, isTrue);
      trail
        ..tick(5100)
        ..tick(5100.0 + _hold.hold.inMilliseconds - 1);
      expect(trail.alphaAt(0), 1);
      trail.tick(5100.0 + _hold.hold.inMilliseconds + LaserTrail.holdFade.inMilliseconds);
      expect(trail.isVisible, isFalse);
    });

    test('while held, frames repaint nothing', () {
      final trail = LaserTrail()..config = _hold;
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      var repaints = 0;
      trail
        ..tick(0)
        ..addListener(() => repaints++);
      for (var t = 16.0; t < 1900; t += 16) {
        trail.tick(t);
      }
      expect(repaints, 0);
      trail.tick(_hold.hold.inMilliseconds + 100.0);
      expect(repaints, 1);
    });

    test('a hovering mouse does not stop the countdown', () {
      final trail = LaserTrail()..config = _hold;
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail
        ..hover(const Offset(40, 0))
        ..tick(0);
      expect(trail.animating, isTrue);
      trail.tick(_hold.hold.inMilliseconds + LaserTrail.holdFade.inMilliseconds + 1.0);
      expect(trail.isEmpty, isTrue);
      expect(trail.headAlpha, 1, reason: 'the hovering dot stays');
    });

    test('after each stroke (the default), points still fade on their own', () {
      final trail = LaserTrail();
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail
        ..tick(0)
        ..tick(LaserConfig.defaultDuration.inMilliseconds / 2);
      expect(trail.alphaAt(0), closeTo(0.5, 1e-9));
    });

    test('switching to fade each stroke while a held trail shows: it fades on from there', () {
      final trail = LaserTrail()..config = _hold;
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail
        ..tick(1000)
        ..tick(2500);
      final start = 1000 + _hold.hold.inMilliseconds;
      trail.tick(start + LaserTrail.holdFade.inMilliseconds / 4); // 3/4 left.
      expect(trail.alphaAt(0), closeTo(0.75, 1e-9));
      final head = trail.headAlpha;
      trail.config = const LaserConfig(); // Each stroke, 1 s.
      expect([for (var i = 0; i < 4; i++) trail.alphaAt(i)], everyElement(closeTo(0.75, 1e-9)));
      expect(trail.headAlpha, closeTo(head, 1e-9));
      final now = trail.now;
      trail.tick(now + 1);
      expect(trail.length, 4, reason: 'not dropped');
      trail.tick(now + 500);
      expect(trail.alphaAt(0), closeTo(0.25, 1e-3));
      trail.tick(now + 760);
      expect(trail.isVisible, isFalse);
    });

    test('switching to fade when I stop while a trail fades: what shows fades on as it was', () {
      final trail = LaserTrail(); // Each stroke, 1 s.
      addTearDown(trail.dispose);
      _stroke(trail, Offset.zero);
      trail
        ..tick(0)
        ..tick(400);
      final head = trail.headAlpha;
      trail.config = _hold;
      expect([for (var i = 0; i < 4; i++) trail.alphaAt(i)], everyElement(closeTo(0.6, 1e-9)));
      expect(trail.headAlpha, closeTo(head, 1e-9));
      trail.tick(700);
      expect(trail.alphaAt(0), closeTo(0.3, 1e-9), reason: 'no flash back');
      // A new stroke is held, while the old one fades out beneath it.
      _stroke(trail, const Offset(0, 50));
      trail.tick(800);
      expect(trail.length, 8);
      trail.tick(1100);
      expect(trail.length, 4, reason: 'the old stroke went');
      expect([for (var i = 0; i < 4; i++) trail.alphaAt(i)], everyElement(1));
      trail.tick(800 + _hold.hold.inMilliseconds + LaserTrail.holdFade.inMilliseconds + 1.0);
      expect(trail.isEmpty, isTrue);
    });

    test('the fade and hold persist; bad values take their defaults', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      const config = LaserConfig(fade: LaserFade.pause, hold: Duration(milliseconds: 3500));
      ToolSettings(store: store)
        ..laser = config
        ..dispose();
      final restored = ToolSettings(store: store);
      expect(restored.laser, config);
      restored.dispose();
      expect(
        LaserConfig.fromJson({'fade': 'never', 'hold': 99999}),
        const LaserConfig(hold: LaserConfig.maxHold),
      );
    });
  });

  testWidgets('on screen, a held trail stays between strokes and goes 2 s after the last', (
    tester,
  ) async {
    final trail = LaserTrail();
    final viewport = ViewportController();
    addTearDown(trail.dispose);
    addTearDown(viewport.dispose);
    final tool = LaserTool(trail, config: () => _hold);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LaserOverlay(trail: trail, viewport: viewport),
      ),
    );
    Future<void> write(Offset from) async {
      tool.down(ToolPointer(screen: from, world: from));
      for (var i = 1; i <= 5; i++) {
        final p = from + Offset(i * 8, 0);
        tool.move(ToolPointer(screen: p, world: p));
        await tester.pump(const Duration(milliseconds: 16));
      }
      tool.up();
      await tester.pump(const Duration(milliseconds: 16));
    }

    await write(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 1500)); // Lift, think…
    await write(const Offset(10, 40)); // …and write on.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(trail.length, 12);
    expect(trail.alphaAt(0), 1, reason: 'the first stroke shows 3 s after it was drawn');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(LaserTrail.holdFade);
    await tester.pump(const Duration(milliseconds: 16));
    expect(trail.isVisible, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the ticker stopped');
  });

  testWidgets('the laser options switch the fade; its slider follows', (tester) async {
    final tools = ToolSettings();
    addTearDown(tools.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: SingleChildScrollView(
            child: SizedBox(width: 320, child: LaserOptionsPanel(tools: tools)),
          ),
        ),
      ),
    );
    expect(find.text('Trail lasts'), findsOneWidget);
    await tester.ensureVisible(find.text('When I stop'));
    await tester.tap(find.text('When I stop'));
    await tester.pump();
    expect(tools.laser.fade, LaserFade.pause);
    expect(find.text('Trail lasts'), findsNothing);
    expect(find.text('Fades after'), findsOneWidget);
    expect(find.text('2.0 s'), findsOneWidget);
    await tester.ensureVisible(find.text('Dot'));
    await tester.tap(find.text('Dot'));
    await tester.pump();
    expect(find.text('When I stop'), findsNothing, reason: 'a dot leaves no trail to fade');
    expect(tester.takeException(), isNull);
  });
}
