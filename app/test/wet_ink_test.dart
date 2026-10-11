import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/pen/pen_profile.dart';
import 'package:len/ink/render/stroke_renderer.dart';

LiveInk drawing(InkTool tool, {int color = 0xFF112233, StrokeStyle? style}) => LiveInk()
  ..begin(tool: tool, color: color, width: 3, style: style)
  ..add(const StrokePoint(0, 0, 0.5));

void main() {
  test('opaque pen ink gets the radius of its outline, in screen pixels', () {
    final live = drawing(InkTool.ballpoint);
    final style = WetInkStyle.of(live, 2)!;
    expect(style.color, 0xFF112233);
    expect(style.radii, hasLength(WetInkStyle.steps + 1));
    final profile = PenProfile.of(InkTool.ballpoint);
    expect(style.radii[5], StrokeRenderer.radiusAt(profile, 3, live.style, 0.5) * 2);
    expect(style.radii.first, lessThanOrEqualTo(style.radii.last));
  });

  test('ink an overlay cannot match exactly is left to Flutter', () {
    expect(WetInkStyle.of(drawing(InkTool.highlighter), 1), isNull, reason: 'translucent');
    expect(WetInkStyle.of(drawing(InkTool.pencil), 1), isNull, reason: 'textured');
    expect(WetInkStyle.of(drawing(InkTool.fountain), 1), isNull, reason: 'nib');
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
    // 17 values, then the kernel (odd length, sums to 1).
    expect(list.length - 17, shape.kernel.length);
    expect(shape.kernel.length.isOdd, isTrue);
    expect(shape.kernel.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    expect(list[9], shape.hookStart);
    expect(list[13], shape.step);
    expect(list[15], shape.fit);
    expect(list[16], shape.cornerK);
    final scaled = shape.scaled(3).toList();
    expect(scaled[0], closeTo(list[0] * 3, 1e-12), reason: 'lengths scale');
    expect(scaled[2], list[2], reason: 'the pressure filter does not');
  });
}
