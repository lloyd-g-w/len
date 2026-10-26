// The stabiliser's string (`StabiliserString`): while the pen pulls the
// ink on the stabiliser's string, slow or fast, a hairline runs from the
// ink's tip to the pen with a ring at the pen; it goes at pen-up, never
// shows when the ink is at the pen (the stabiliser off, the pen back
// within the string) or with its setting off, and is never part of the
// stroke.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/pen_stabiliser.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ink/render/stabiliser_string.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late LiveInk live;
  late ViewportController viewport;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController()..setSize(const Size(400, 300));
    tools = ToolSettings(stylusOnly: true);
    live = LiveInk();
    input = InkInputController(model: model, viewport: viewport, tools: tools, live: live);
  });

  tearDown(() {
    model.dispose();
    live.dispose();
    db.close();
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: CustomPaint(
            painter: LiveInkPainter(live: live, viewport: viewport),
          ),
        ),
      ),
    ),
  );

  /// Writes a line at [speed] px/s for [ms], one stylus sample a
  /// millisecond.
  void write(double speed, {int ms = 400}) {
    input.handleDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(50, 150),
        pressure: 0.5,
      ),
    );
    for (var t = 1; t <= ms; t++) {
      input.handleMove(
        PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: Offset(50 + speed * t / 1000, 150),
          pressure: 0.5,
          timeStamp: Duration(milliseconds: t),
        ),
      );
    }
  }

  void lift() => input.handleUp(
    const PointerUpEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      timeStamp: Duration(seconds: 1),
    ),
  );

  void stabiliser(double s) =>
      tools.updateConfig(tools.activeInk, (c) => c.copyWith(streamline: s));

  for (final speed in [60.0, 1500.0]) {
    testWidgets('a pen at $speed px/s pulls the ink on a string, which goes at pen-up', (
      tester,
    ) async {
      stabiliser(1);
      await show(tester);
      write(speed);
      await tester.pump();
      final from = live.stringFrom!, to = live.stringTo!;
      // From the ink's tip, held back, to the pen: as far at any speed once
      // the string has grown (`PenStabiliser`).
      expect(to.dx, closeTo(50 + speed * 0.4, 1e-9));
      expect(
        to.dx - from.dx,
        greaterThan(StabiliserString.hiddenBelow + StabiliserString.fadeOver),
      );
      if (speed > 1000) expect(to.dx - from.dx, closeTo(StabiliserParams.maxRadius, 1e-6));
      expect(from.dx, closeTo(live.points.last.x, 1));
      final painter = find.byType(CustomPaint);
      expect(
        painter,
        paints
          ..path()
          ..line()
          ..circle(radius: StabiliserString.ringRadius),
      );
      lift();
      await tester.pump();
      expect(live.stringFrom, isNull);
      expect(painter, isNot(paints..circle()));
      // The ink caught up with the pen (to within the points' spacing,
      // `PointSpacing`), along the line, and the string is no part of it.
      final stroke = model.history.takeUndo()!.added.single;
      expect(stroke.points.last.x, closeTo(to.dx, 0.75));
      expect(stroke.points.every((p) => p.y == 150), isTrue);
    });
  }

  testWidgets('no string when the ink is at the pen or the setting is off', (tester) async {
    await show(tester);
    // The default stabiliser (a 3 px string): the pen 1.5 px from where
    // it landed pulls nothing.
    write(1.5, ms: 1000);
    await tester.pump();
    expect(live.stringFrom, isNotNull);
    expect(find.byType(CustomPaint), isNot(paints..circle()));
    lift();
    // Off: the ink trails the pen, but shows no string.
    stabiliser(1);
    tools.showStabiliserString = false;
    write(60);
    await tester.pump();
    expect(live.stringFrom, isNull);
    expect(find.byType(CustomPaint), isNot(paints..circle()));
    lift();
    // Stabiliser off: the ink is under the nib.
    stabiliser(0);
    tools.showStabiliserString = true;
    write(60);
    expect(live.stringFrom, isNull);
    lift();
  });

  test('the string fades in over a few px', () {
    expect(StabiliserString.opacityFor(1), 0);
    expect(StabiliserString.opacityFor(StabiliserString.hiddenBelow), 0);
    expect(StabiliserString.opacityFor(3.5), inExclusiveRange(0, 1));
    expect(StabiliserString.opacityFor(10), 1);
  });
}
