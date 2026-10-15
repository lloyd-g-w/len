import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/palm_guard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// A palm is a palm across the app, not only on the canvas it rests on
/// (R15-4).
void main() {
  const stylus = PointerDeviceKind.stylus;
  const touch = PointerDeviceKind.touch;
  PointerDownEvent down(int id, PointerDeviceKind kind, [int ms = 0]) => PointerDownEvent(
    pointer: id,
    kind: kind,
    buttons: kPrimaryButton,
    timeStamp: Duration(milliseconds: ms),
  );
  PointerUpEvent up(int id, PointerDeviceKind kind, [int ms = 0]) => PointerUpEvent(
    pointer: id,
    kind: kind,
    timeStamp: Duration(milliseconds: ms),
  );

  group('PalmGuard', () {
    late List<int> cancelled;
    late PalmGuard guard;
    setUp(() {
      cancelled = [];
      guard = PalmGuard(cancel: cancelled.add);
    });

    test('cancels touches landing while the pen touches, and those down when it lands', () {
      guard
        ..handleEvent(down(1, touch)) // A palm before the pen.
        ..handleEvent(down(2, stylus));
      expect(cancelled, [1]);
      guard.handleEvent(down(3, touch)); // A palm while writing.
      expect(cancelled, [1, 3]);
      guard
        ..handleEvent(up(2, stylus))
        ..handleEvent(down(4, touch)); // The pen lifted: a finger works.
      expect(cancelled, [1, 3]);
    });

    test('a hovering pen leaves taps alone (the other hand on Undo)', () {
      guard
        ..handleEvent(const PointerHoverEvent(kind: stylus))
        ..handleEvent(down(1, touch))
        ..handleEvent(up(1, touch));
      expect(cancelled, isEmpty);
      expect(guard.stylusNear(Duration.zero, within: const Duration(milliseconds: 300)), isTrue);
    });
  });

  test('a palm on one canvas is ignored while the pen hovers over another', () {
    final db = AppDatabase.inMemory();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    final live = LiveInk();
    final guard = PalmGuard(cancel: (_) {});
    final viewport = ViewportController()..setSize(const Size(800, 600));
    final input = InkInputController(
      model: model,
      viewport: viewport,
      tools: ToolSettings(stylusOnly: true),
      live: live,
      palms: guard,
    );
    addTearDown(() {
      live.dispose();
      model.dispose();
      db.close();
    });
    // The pen hovers over the other pane; this pane sees only the palm.
    guard.handleEvent(const PointerHoverEvent(kind: stylus, timeStamp: Duration(seconds: 1)));
    input
      ..handleDown(
        const PointerDownEvent(
          pointer: 7,
          position: Offset(100, 100),
          timeStamp: Duration(milliseconds: 1100),
        ),
      )
      ..handleMove(
        const PointerMoveEvent(
          pointer: 7,
          position: Offset(200, 200),
          timeStamp: Duration(milliseconds: 1150),
        ),
      );
    expect(input.navigates(7), isFalse);
    expect(viewport.offset, Offset.zero);
  });

  testWidgets('a palm resting on a button while the pen writes taps nothing when lifted', (
    tester,
  ) async {
    var taps = 0;
    final guard = PalmGuard()..attach();
    addTearDown(guard.detach);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () => taps++, child: const Text('Undo')),
        ),
      ),
    );
    final at = tester.getCenter(find.text('Undo'));
    final palm = await tester.createGesture(kind: touch);
    await palm.down(at);
    final pen = await tester.createGesture(kind: stylus, pointer: 9);
    await pen.down(const Offset(5, 5));
    await tester.pump();
    await pen.up();
    await palm.up();
    await tester.pump();
    expect(taps, 0);
    // Without the pen, the same tap works.
    await tester.tap(find.text('Undo'));
    expect(taps, 1);
  });
}
