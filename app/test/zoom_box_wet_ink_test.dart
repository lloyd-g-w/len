import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/editor/zoom/zoom_box_viewport.dart';
import 'package:len/ink/input/sample_source.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/platform/low_latency_ink_native.dart';

class _NoSamples implements SampleSource {
  @override
  void begin(PointerDownEvent down) {}
  @override
  List<PointerSample> between(PointerEvent event) => const [];
  @override
  void end({double taperEnd = 0}) {}
  @override
  void hover(PointerHoverEvent event) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('low-latency ink in the zoom box is clipped to the box where it lies on the screen', () {
    final sent = <List<Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      lowLatencyInkChannel,
      (data) async {
        sent.add(const StandardMessageCodec().decodeMessage(data) as List<Object?>);
        return null;
      },
    );
    final view = ZoomBoxViewport(onPan: (_) {}, onZoom: (_, _) {})
      ..show(scale: 4, offset: const Offset(-40, -400), size: const Size(600, 200));
    final style = WetInkStyle.forNextStroke(ToolSettings(), 4);
    expect(style, isNotNull);
    final source = LowLatencySource(
      _NoSamples(),
      () => style,
      () => style,
      () => view.wetInkView(page: const Rect.fromLTWH(0, 0, 500, 800)),
      () => 1,
    );
    // The box lies 600 px down the screen; its events are box-local.
    source.begin(
      const PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 650),
      ).transformed(Matrix4.translationValues(0, -600, 0)),
    );
    final begin = sent.lastWhere((m) => m.first == 'begin');
    expect(begin.last, [0.0, 600.0, 600.0, 800.0]);
  });
}
