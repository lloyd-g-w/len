import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/viewport.dart';

LiveInk drawing(InkTool tool, {int color = 0xFF112233, StrokeStyle? style}) => LiveInk()
  ..begin(tool: tool, color: color, width: 3, style: style)
  ..add(const StrokePoint(0, 0, 0.5));

void main() {
  test('opaque pen ink gets the radius of its outline, in screen pixels', () {
    final live = drawing(InkTool.ballpoint);
    final style = WetInkStyle.of(live, 2)!;
    expect(style.color, 0xFF112233);
    expect(style.radii, hasLength(WetInkStyle.steps + 1));
    final spec = StrokeRenderer.specFor(InkTool.ballpoint, 3, live.style);
    expect(style.radii[5], spec.radiusFor(0.5) * 2);
    expect(style.radii.first, lessThanOrEqualTo(style.radii.last));
  });

  test('ink an overlay cannot match exactly is left to Flutter', () {
    expect(WetInkStyle.of(drawing(InkTool.highlighter), 1), isNull, reason: 'translucent');
    final opaqueHighlighter = drawing(InkTool.highlighter, style: const StrokeStyle());
    expect(WetInkStyle.of(opaqueHighlighter, 1), isNull, reason: 'flat caps');
    expect(WetInkStyle.of(drawing(InkTool.ballpoint, color: 0x80112233), 1), isNull);
    expect(
      WetInkStyle.of(drawing(InkTool.ballpoint, style: const StrokeStyle(opacity: 0.5)), 1),
      isNull,
    );
  });

  test('nothing while not drawing or once the stroke is straightened', () {
    expect(WetInkStyle.of(LiveInk(), 1), isNull);
    final live = drawing(InkTool.ballpoint)..straightened = true;
    expect(WetInkStyle.of(live, 1), isNull);
  });

  test('the overlay gets the outline rules in a fixed order (WetInkOverlay.kt reads it)', () {
    final shape = WetInkStyle.of(drawing(InkTool.ballpoint), 2)!.shape;
    final list = shape.toList();
    // 21 values (including cap shape and start taper), then the kernel.
    expect(list.length - 21, shape.kernel.length);
    expect(shape.kernel.length.isOdd, isTrue);
    expect(shape.kernel.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    expect(list[9], shape.hookStart);
    expect(list[13], shape.step);
    expect(list[15], shape.fit);
    expect(list[16], shape.cornerK);
    expect(list[17], shape.lag);
    expect(list[18], shape.startReach);
    expect(list[19], shape.flat ? 1 : 0);
    expect(list[20], shape.taperStart);
    final scaled = shape.scaled(3).toList();
    expect(scaled[0], closeTo(list[0] * 3, 1e-12), reason: 'lengths scale');
    expect(scaled[2], list[2], reason: 'the pressure filter does not');
  });

  group('the overlay draws only in the writing area', () {
    ViewportController viewport({Rect? page}) => ViewportController()
      ..setSize(const Size(800, 600))
      ..setView(scale: 2, offset: const Offset(10, 20))
      ..contentBounds = page;

    test('a canvas: the surface less the chrome', () {
      final view = WetInkView.of(viewport(), covered: const EdgeInsets.only(top: 60, bottom: 40));
      expect(view.clip, const Rect.fromLTRB(0, 60, 800, 560));
      expect(view.scale, 2);
      expect(view.offset, const Offset(10, 20));
    });

    test('a page: only the page, where its ink is clipped too', () {
      final v = viewport(page: const Rect.fromLTWH(0, 0, 300, 400));
      final view = WetInkView.of(v, covered: const EdgeInsets.only(top: 60));
      expect(view.clip, Rect.fromLTRB(v.offset.dx, 60, v.offset.dx + 600, 600));
    });

    test('a moved view is another transform', () {
      final a = WetInkView.of(viewport());
      expect(a.sameTransform(WetInkView.of(viewport())), isTrue);
      final moved = viewport()..panBy(const Offset(1, 0));
      expect(a.sameTransform(WetInkView.of(moved)), isFalse);
    });
  });
}
