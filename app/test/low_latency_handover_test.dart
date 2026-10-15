// What Dart tells the Android low-latency overlay around the hand-over, frame
// by frame (`LowLatencySource`, `LowLatencyFrames`; the overlay's side is
// `WetInkHandoverTest.kt`): one report per built frame, a few more after
// the last input so the overlay can judge the last frame on screen, `end`
// right after the report of the frame with the committed stroke, and the
// overlay's ink taken away with the frame that no longer shows it — not
// left behind alone (a bounce, a scribble that erased) and not at the old
// place on the screen when the view moves (the zoom window moving on).
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/sample_source.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/platform/low_latency_frames.dart';
import 'package:len/platform/low_latency_ink_native.dart';

class _NoSamples implements SampleSource {
  @override
  void begin(PointerDownEvent down) {}
  @override
  List<PointerSample> between(PointerEvent event) => const [];
  @override
  void end({Stroke? committed}) {}
  @override
  void hover(PointerHoverEvent event) {}
}

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late LiveInk live;
  late ViewportController viewport;
  late InkInputController input;
  final sent = <List<Object?>>[];
  var t = 0;

  setUp(() {
    t = 1000000;
    lowLatencyFrames.reset();
    sent.clear();
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    tools = ToolSettings(stylusOnly: true);
    live = LiveInk();
    viewport = ViewportController()..setSize(const Size(800, 600));
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      samples: LowLatencySource(
        _NoSamples(),
        () => WetInkStyle.of(live, viewport.scale),
        () => WetInkStyle.forNextStroke(tools, viewport.scale),
        () => WetInkView.of(viewport),
        () => 2,
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      lowLatencyInkChannel,
      (data) async {
        sent.add(const StandardMessageCodec().decodeMessage(data) as List<Object?>);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      lowLatencyInkChannel,
      null,
    );
    model.dispose();
    db.close();
  });

  Duration at() => Duration(microseconds: t);
  PointerDownEvent down(Offset p) => PointerDownEvent(
    pointer: 1,
    device: 3,
    kind: PointerDeviceKind.stylus,
    position: p,
    pressure: 0.5,
    timeStamp: at(),
  );
  PointerMoveEvent move(Offset p) => PointerMoveEvent(
    pointer: 1,
    device: 3,
    kind: PointerDeviceKind.stylus,
    position: p,
    pressure: 0.5,
    timeStamp: at(),
  );
  PointerUpEvent up(Offset p) => PointerUpEvent(
    pointer: 1,
    device: 3,
    kind: PointerDeviceKind.stylus,
    position: p,
    timeStamp: at(),
  );

  /// The kinds of message sent since the last call ("progress" as "p").
  List<String> kinds() {
    final out = [for (final m in sent) m.first == 'progress' ? 'p' : m.first as String];
    sent.clear();
    return out;
  }

  /// Writes a wavy line of [n] moves from [from], a frame every two moves.
  Future<void> write(WidgetTester tester, Offset from, {int n = 24, bool lift = true}) async {
    input.handleDown(down(from));
    for (var i = 1; i <= n; i++) {
      t += 4000;
      input.handleMove(move(from + Offset(i * 6.0, (i % 6) * 3.0)));
      if (i.isEven) await tester.pump(const Duration(milliseconds: 8));
    }
    if (!lift) return;
    t += 4000;
    input.handleUp(up(from + Offset(n * 6.0, (n % 6) * 3.0)));
  }

  testWidgets('one report per frame, then the end after the committed frame\'s and three more', (
    tester,
  ) async {
    await write(tester, const Offset(100, 100));
    final writing = kinds();
    expect(writing.first, 'begin');
    expect(writing.skip(1), everyElement('p'), reason: 'one report per frame: $writing');
    expect(writing.length - 1, 12);
    // The frame with the committed stroke, then the trailing ones; then
    // no frames are asked for.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(kinds(), ['p', 'end', 'p', 'p', 'p']);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('frame ids count up, one per frame', (tester) async {
    await write(tester, const Offset(100, 100), lift: false);
    final ids = [
      for (final m in sent)
        if (m.first == 'progress') m[2]! as int,
    ];
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i], ids[i - 1] + 1);
    }
    input.handleUp(up(const Offset(300, 100)));
    await tester.pump(const Duration(milliseconds: 8));
  });

  testWidgets('a bounce goes with the frame without it, not later and alone', (tester) async {
    // A stroke, then the pen bouncing where it lifted.
    await write(tester, const Offset(100, 100));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    kinds();
    t += 30000;
    input.handleDown(down(const Offset(244, 100)));
    t += 20000;
    input.handleUp(up(const Offset(244, 100)));
    expect(model.loadedStrokeCount, 1, reason: 'the bounce is dropped');
    expect(kinds(), ['begin'], reason: 'nothing until the frame without it is built');
    await tester.pump(const Duration(milliseconds: 8));
    expect(kinds(), ['p', 'cancel']);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  });

  testWidgets('the view moving after the lift takes the overlay\'s ink away', (tester) async {
    await write(tester, const Offset(100, 100));
    kinds();
    await tester.pump(const Duration(milliseconds: 8));
    expect(kinds(), ['p', 'end']);
    await tester.pump(const Duration(milliseconds: 8));
    kinds();
    // The zoom window moving on, a scroll: the stroke is elsewhere now.
    viewport.panBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 8));
    expect(kinds(), contains('cancel'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  });

  testWidgets('a view moved by the lift\'s own frame cancels instead of ending', (tester) async {
    await write(tester, const Offset(100, 100));
    kinds();
    viewport.panBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 8));
    expect(kinds(), ['p', 'cancel']);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  });

  testWidgets('the view moving mid-stroke cancels with the frame that moves it', (tester) async {
    await write(tester, const Offset(100, 100), lift: false);
    kinds();
    viewport.panBy(const Offset(0, -40));
    t += 4000;
    input.handleMove(move(const Offset(260, 120)));
    expect(kinds(), isEmpty, reason: 'Flutter still shows the stroke where it was');
    await tester.pump(const Duration(milliseconds: 8));
    expect(kinds(), ['p', 'cancel']);
    t += 4000;
    input.handleUp(up(const Offset(262, 120)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(kinds(), everyElement('p'));
  });

  test('trailing frames cover the overlay\'s pipeline rule', () {
    // WetInkHandover.PIPELINE_FRAMES: the frame three frames later must come.
    expect(LowLatencyFrames.trailingFrames, 3);
  });
}
