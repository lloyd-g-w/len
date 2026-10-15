import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/templates/paper_swatch.dart';
import 'package:len/ink/render/paper_painter.dart';

/// The paper options' "actual size" preview draws the paper as the canvas
/// does at 100 %, on any screen density.
void main() {
  testWidgets('the swatch on a 2× screen draws what the canvas draws at 100 %', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // Millimetre lines: too dense to show at 100 % (fewer than 7 logical
    // pixels apart), thinned to fade there.
    const template = PageTemplate(paper: Paper(PaperStyle.graph, look: PaperLook(lineWeight: 0.5)));
    const size = Size(200, 120);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox.fromSize(
              size: size,
              child: const PaperSwatch(template: template),
            ),
          ),
        ),
      ),
    );
    final swatch = await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData())!;
      image.dispose();
      return bytes;
    });

    // The canvas at 100 %: a logical pixel per unit, on a 2× screen.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = template.color.paper);
    PaperRenderer.paintPattern(
      canvas,
      template.paper,
      template.color,
      area,
      page: Offset.zero & template.size,
      scale: 1,
    );
    final expected = await tester.runAsync(() async {
      final image = await recorder.endRecording().toImage(400, 240);
      final bytes = (await image.toByteData())!;
      image.dispose();
      return bytes;
    });

    // Compared away from the swatch's border.
    var differing = 0;
    for (var y = 8; y < 232; y++) {
      for (var x = 8; x < 392; x++) {
        final i = 4 * (y * 400 + x);
        if ((swatch!.getUint8(i) - expected!.getUint8(i)).abs() > 2) differing++;
      }
    }
    expect(differing, 0);
  });
}
