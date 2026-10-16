import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/paper.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso_path.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_painter.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/app_theme.dart';

import 'data_test.dart' show FakeClock;

/// The lasso on Dark paper (UX_AUDIT R23-6): ruling blue alone is 2.9:1
/// there; a paper-coloured band under the line keeps it readable.
void main() {
  test('the lasso line has a light band under it on dark paper', () async {
    final db = AppDatabase.inMemory();
    final clock = FakeClock();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    );
    final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
    final lasso = LassoPath()
      ..begin(const Offset(10, 50))
      ..add(const Offset(190, 50));
    addTearDown(() {
      selection.dispose();
      model.dispose();
    });
    const size = Size(200, 100);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(PaperColor.dark.paper, BlendMode.src);
    SelectionPainter(
      selection: selection,
      lasso: lasso,
      viewport: ViewportController()..setSize(size),
      accent: AppTheme.seed,
      handleFill: Palette.paper,
    ).paint(canvas, size);
    final image = await recorder.endRecording().toImage(200, 100);
    final bytes = (await image.toByteData())!;
    // A dash starts at the lasso's first point: just beside the 1.5-px blue
    // line, the band lightens the dark paper.
    final i = (48 * 200 + 12) * 4;
    final luminance = Color.fromARGB(
      255,
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    ).computeLuminance();
    // (Without it: the paper, 0.02.)
    expect(luminance, greaterThan(0.4));
  });
}
