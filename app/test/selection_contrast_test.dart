import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso_path.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_painter.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;

/// The lasso and the selection frame on Dark paper: ruling blue alone is
/// 2.9:1 there; the line is two-tone (accent dashes over a paper-coloured
/// hairline), so its gaps light up dark paper while light paper shows clean
/// blue dashes. Nothing thicker than the hairline is drawn.
void main() {
  late SurfaceModel model;
  late SelectionController selection;

  setUp(() {
    final db = AppDatabase.inMemory();
    final clock = FakeClock();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    );
    selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
    addTearDown(() {
      selection.dispose();
      model.dispose();
    });
  });

  /// Paints [lasso] (and [selection]) over [paper]; the pixels, RGBA.
  Future<ByteData> paint(LassoPath lasso, Color paper) async {
    const size = Size(200, 100);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(paper, BlendMode.src);
    SelectionPainter(
      selection: selection,
      lasso: lasso,
      viewport: ViewportController()..setSize(size),
      accent: AppTheme.seed,
      handleFill: Palette.paper,
    ).paint(canvas, size);
    final image = await recorder.endRecording().toImage(200, 100);
    return (await image.toByteData())!;
  }

  Color at(ByteData bytes, int x, int y) {
    final i = (y * 200 + x) * 4;
    return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  }

  // The line along y = 50.5 covers pixel row 50; dashes of 5 from x = 10
  // (on 10–15, off 15–18, on 18–23 …).
  LassoPath line() => LassoPath()
    ..begin(const Offset(10, 50.5))
    ..add(const Offset(190, 50.5));

  test('the lasso line lights its gaps on dark paper', () async {
    final bytes = await paint(line(), PaperColor.dark.paper);
    // (Without the light hairline: the paper, 0.02.)
    expect(at(bytes, 15, 50).computeLuminance(), greaterThan(0.4), reason: 'a gap');
    expect(at(bytes, 11, 50), isSameColorAs(AppTheme.seed), reason: 'a dash');
    expect(at(bytes, 15, 47), isSameColorAs(PaperColor.dark.paper), reason: 'no band');
  });

  test('on light paper the lasso is blue dashes and nothing else', () async {
    final bytes = await paint(line(), Palette.paper);
    expect(at(bytes, 11, 50), isSameColorAs(AppTheme.seed));
    expect(at(bytes, 15, 50), isSameColorAs(Palette.paper));
    expect(at(bytes, 100, 30), isSameColorAs(Palette.paper), reason: 'no fill');
  });

  test('the rectangle lasso is a closed hairline box', () async {
    final lasso = LassoPath()..rectangle(const Offset(20.5, 20.5), const Offset(180.5, 80.5));
    final bytes = await paint(lasso, PaperColor.dark.paper);
    // Its left side (x = 20.5 covers column 20) runs back up from the
    // bottom: some of it dashed, some of it light.
    final side = [for (var y = 22; y < 79; y++) at(bytes, 20, y).computeLuminance()];
    expect(side.where((l) => l > 0.4), isNotEmpty);
    expect(at(bytes, 100, 50), isSameColorAs(PaperColor.dark.paper), reason: 'no fill');
  });

  test('the frame and its handles show on dark paper', () async {
    final lasso = LassoPath();
    final stroke = Stroke(
      id: 'a',
      surfaceId: 's',
      tool: InkTool.ballpoint,
      points: const [StrokePoint(60, 40, 0.5), StrokePoint(140, 60, 0.5)],
      color: 0xFFFFFFFF,
      width: 2,
      createdAt: 0,
    );
    model.addStroke(stroke);
    selection.select([stroke], const []);
    // The viewport is the identity: world is screen.
    final corner = selection.frame!.corners.first;
    final bytes = await paint(lasso, PaperColor.dark.paper);
    // A corner handle: a paper disc.
    expect(at(bytes, corner.dx.round(), corner.dy.round()).computeLuminance(), greaterThan(0.4));
  });
}
