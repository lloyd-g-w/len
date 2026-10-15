import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// A contact the platform cancels mid-stroke (the window lost focus,
/// rotated, a system gesture) keeps a pen's ink; a finger's goes (R15-5).
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late LiveInk live;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    live = LiveInk();
    input = InkInputController(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: ToolSettings(stylusOnly: false),
      live: live,
    );
  });

  tearDown(() {
    live.dispose();
    model.dispose();
    db.close();
  });

  void writeThenCancel(PointerDeviceKind kind) {
    input.handleDown(
      PointerDownEvent(
        kind: kind,
        position: const Offset(10, 100),
        buttons: kPrimaryButton,
        pressure: 0.5,
      ),
    );
    for (var x = 20.0; x <= 300; x += 20) {
      input.handleMove(
        PointerMoveEvent(
          kind: kind,
          position: Offset(x, 100),
          buttons: kPrimaryButton,
          pressure: 0.5,
          timeStamp: Duration(milliseconds: x.round()),
        ),
      );
    }
    input.handleCancel(PointerCancelEvent(kind: kind, timeStamp: const Duration(seconds: 1)));
  }

  test('a cancelled pen stroke is kept as written', () {
    writeThenCancel(PointerDeviceKind.stylus);
    expect(model.loadedStrokeCount, 1);
    expect(live.isDrawing, isFalse);
    expect(model.history.canUndo, isTrue);
  });

  test('a cancelled finger stroke goes (a pinch\'s start or a palm)', () {
    writeThenCancel(PointerDeviceKind.touch);
    expect(model.loadedStrokeCount, 0);
    expect(live.isDrawing, isFalse);
  });
}
