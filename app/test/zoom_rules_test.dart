import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/zoom/zoom_frame.dart';

void main() {
  const box = Size(600, 200);
  const page = Rect.fromLTWH(0, 0, 600, 800);
  const rules = ZoomRules(box: box, lineStart: 60, lineEnd: 600, page: page);
  // Scale 3: the frame is 200 × 66.7 on the page.
  const frame = ZoomFrame(surfaceId: 'p', origin: Offset(60, 100), scale: 3);

  group('ZoomFrame', () {
    test('its rectangle is the box divided by the scale', () {
      expect(frame.rectFor(box), const Rect.fromLTWH(60, 100, 200, 200 / 3));
    });

    test('has value equality', () {
      expect(frame, const ZoomFrame(surfaceId: 'p', origin: Offset(60, 100), scale: 3));
      expect(frame == frame.copyWith(scale: 2), isFalse);
    });
  });

  group('ZoomRules', () {
    test('opens showing three ruled lines, within the page limits', () {
      // 3 lines of 20 fill 200 px: 60 units tall, 180 wide: clamped up to 0.2 of the page.
      expect(rules.startScale(pitch: 20, viewWidth: 0), closeTo(600 / 180, 1e-9));
      expect(rules.startScale(pitch: 2, viewWidth: 0), closeTo(600 / 120, 1e-9));
      expect(rules.startScale(pitch: 100, viewWidth: 0), closeTo(600 / 360, 1e-9));
      // No lines: a third of the page; on a canvas, a third of the view.
      expect(rules.startScale(viewWidth: 0), closeTo(3, 1e-9));
      const canvas = ZoomRules(box: box, lineStart: 0, lineEnd: 1000);
      expect(canvas.startScale(viewWidth: 900), closeTo(2, 1e-9));
    });

    test('the advance zone is the frame\'s right part', () {
      expect(rules.zoneStart(frame), closeTo(60 + 200 * 0.7, 1e-9));
      expect(rules.inZone(frame, 190), isFalse);
      expect(rules.inZone(frame, 205), isTrue);
      expect(rules.advancesNow(frame, 205), isFalse);
      expect(rules.advancesNow(frame, 245), isTrue);
    });

    test('keeps the frame on the page, centred where the page is narrower', () {
      expect(rules.clamp(frame, const Offset(-10, -10)), Offset.zero);
      expect(rules.clamp(frame, const Offset(500, 790)), Offset(400, 800 - 200 / 3));
      const wide = ZoomFrame(surfaceId: 'p', origin: Offset.zero, scale: 0.5);
      expect(rules.clamp(wide, const Offset(30, 0)).dx, (600 - 1200) / 2);
      const canvas = ZoomRules(box: box, lineStart: 0, lineEnd: 1000);
      expect(canvas.clamp(frame, const Offset(-50, -50)), const Offset(-50, -50));
    });

    test('advancing leaves the last ink a quarter into the frame', () {
      final move = rules.advance(frame, 230, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, const Offset(230 - 200 * ZoomRules.keep, 100));
    });

    test('the frame never runs past the line\'s end', () {
      const late = ZoomFrame(surfaceId: 'p', origin: Offset(350, 100), scale: 3);
      final move = rules.advance(late, 540, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, const Offset(400, 100));
    });

    test('at the end of the line it wraps to the start of the next', () {
      const end = ZoomFrame(surfaceId: 'p', origin: Offset(400, 100), scale: 3);
      final move = rules.advance(end, 590, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, const Offset(60, 120));
    });

    test('a new line at the bottom of a page goes on to the next page', () {
      final bottom = 800 - 200 / 3;
      // Near the bottom it stops at the bottom first…
      final last = rules.newLine(frame.copyWith(origin: Offset(300, bottom - 5)), lineStep: 20);
      expect((last as ZoomMoveTo).origin, Offset(60, bottom));
      // …then turns the page, near its top.
      final next = rules.newLine(frame.copyWith(origin: Offset(300, bottom)), lineStep: 20);
      expect((next as ZoomNextPage).origin, Offset(60, 800 * ZoomRules.topMargin));
    });

    test('on a canvas a new line just moves down', () {
      const canvas = ZoomRules(box: box, lineStart: -40, lineEnd: 1000);
      final move = canvas.newLine(frame, lineStep: 30) as ZoomMoveTo;
      expect(move.origin, const Offset(-40, 130));
    });

    test('sizing keeps the frame within a page\'s limits', () {
      expect(rules.scaleForWidth(300), 2);
      expect(rules.scaleForWidth(10), closeTo(600 / (600 * ZoomRules.minPageFraction), 1e-9));
      expect(rules.scaleForWidth(5000), 1);
      const canvas = ZoomRules(box: box, lineStart: 0, lineEnd: 1000);
      expect(canvas.scaleForWidth(5000), closeTo(600 / 5000, 1e-9));
    });

    test('a line steps by whole ruled lines as tall as its ink', () {
      double step(double ink) => ZoomRules.lineStep(frameHeight: 90, inkHeight: ink, pitch: 20);
      expect(step(0), 20);
      expect(step(15), 20);
      expect(step(30), 20); // Descenders: still one line.
      expect(step(40), 40);
      // Without lines: a third of the frame.
      expect(ZoomRules.lineStep(frameHeight: 90, inkHeight: 10), 30);
    });
  });

  group('ZoomRules right to left', () {
    // Lines start at x 540 (the frame's right edge) and end at the page's left.
    const rtl = ZoomRules(box: box, lineStart: 540, lineEnd: 0, page: page, rightToLeft: true);
    // The frame at the line's start: 340 – 540.
    const start = ZoomFrame(surfaceId: 'p', origin: Offset(340, 100), scale: 3);

    test('the advance zone is the frame\'s left part, where the ink ends at its left', () {
      expect(rtl.zoneStart(start), closeTo(540 - 200 * 0.7, 1e-9));
      expect(rtl.inkEnd(const Rect.fromLTRB(380, 0, 420, 10)), 380);
      expect(rtl.inZone(start, 410), isFalse);
      expect(rtl.inZone(start, 395), isTrue);
      expect(rtl.advancesNow(start, 395), isFalse);
      expect(rtl.advancesNow(start, 355), isTrue);
    });

    test('advancing moves leftwards, the last ink a quarter into the frame', () {
      final move = rtl.advance(start, 370, lineStep: 20) as ZoomMoveTo;
      expect(move.origin.dx + 200 - 370, closeTo(200 * ZoomRules.keep, 1e-9));
      expect(move.origin.dy, 100);
    });

    test('the frame never runs past the page\'s left edge', () {
      const late = ZoomFrame(surfaceId: 'p', origin: Offset(50, 100), scale: 3);
      final move = rtl.advance(late, 10, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, const Offset(0, 100));
    });

    test('at the end of the line it wraps back to the right', () {
      const end = ZoomFrame(surfaceId: 'p', origin: Offset(0, 100), scale: 3);
      final move = rtl.advance(end, 5, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, const Offset(340, 120));
    });

    test('a new line past a page\'s bottom starts the next page at the right', () {
      final bottom = 800 - 200 / 3;
      final next = rtl.newLine(start.copyWith(origin: Offset(10, bottom)), lineStep: 20);
      expect((next as ZoomNextPage).origin, Offset(340, 800 * ZoomRules.topMargin));
    });

    test('ink lifted behind the frame (to its right) leaves it where it is', () {
      const mid = ZoomFrame(surfaceId: 'p', origin: Offset(200, 100), scale: 3);
      final move = rtl.advance(mid, 380, lineStep: 20) as ZoomMoveTo;
      expect(move.origin, mid.origin);
    });
  });
}
