import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/pointer_activity.dart';

void main() {
  var now = DateTime(2026, 10, 12, 10);
  late PointerActivity activity;
  setUp(() => activity = PointerActivity(now: () => now));

  test('active while any pointer is down; the last release is the last activity', () {
    expect(activity.isActive, isFalse);
    activity.handleEvent(const PointerDownEvent(pointer: 1));
    activity.handleEvent(const PointerDownEvent(pointer: 2));
    now = now.add(const Duration(seconds: 5));
    expect(activity.lastActivity, now, reason: 'down = active now');
    activity.handleEvent(const PointerUpEvent(pointer: 1));
    expect(activity.isActive, isTrue);
    activity.handleEvent(const PointerCancelEvent(pointer: 2));
    expect(activity.isActive, isFalse);
    final released = now;
    now = now.add(const Duration(seconds: 1));
    expect(activity.lastActivity, released);
  });

  test('trackpad pan/zoom and wheel scrolling count; mouse hovers do not', () {
    activity.handleEvent(const PointerPanZoomStartEvent(pointer: 3));
    expect(activity.isActive, isTrue);
    activity.handleEvent(const PointerPanZoomEndEvent(pointer: 3));
    expect(activity.isActive, isFalse);

    now = now.add(const Duration(seconds: 1));
    activity.handleEvent(const PointerScrollEvent(scrollDelta: Offset(0, 20)));
    expect(activity.lastActivity, now);

    final scrolled = now;
    now = now.add(const Duration(seconds: 1));
    activity.handleEvent(const PointerHoverEvent(kind: PointerDeviceKind.mouse));
    expect(activity.lastActivity, scrolled);
    activity.handleEvent(const PointerHoverEvent(kind: PointerDeviceKind.stylus));
    expect(activity.lastActivity, now, reason: 'a hovering pen is about to write');
  });

  test('attach watches the router; detach stops and forgets', () {
    final router = PointerRouter();
    activity.attach(router);
    router.route(const PointerDownEvent(pointer: 4));
    expect(activity.isActive, isTrue);
    activity.detach();
    expect(activity.isActive, isFalse);
    router.route(const PointerDownEvent(pointer: 5));
    expect(activity.isActive, isFalse);
  });
}
