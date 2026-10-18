import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/elements/element_renderer.dart';
import 'package:len/ink/elements/shown_text_layout.dart';
import 'package:len/ink/elements/text_hit_test.dart';
import 'package:len/ink/elements/text_layout.dart';
import 'package:len/ink/fonts/text_fonts.dart';

/// UX_AUDIT R26-30: text in a missing font stays inside its frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(TextFonts.reset);

  const text = 'Handwriting quickly fills the box line after line after line';
  final missing = TextFont.user('0' * 32);

  /// A box whose frame was measured in Caveat (narrower than the fallback
  /// Sans), holding its text in [font].
  SurfaceElement box(TextFont font, {List<ParaStyle> paras = const []}) {
    TextData data(TextFont f) => TextData.rich(text: text, spans: const [], paras: paras, font: f);
    final height = TextLayout.heightOf(data(TextFont.caveat), 120);
    return SurfaceElement(
      id: 'box',
      surfaceId: 'page',
      type: ElementType.text.name,
      rect: Rect.fromLTWH(10, 10, 120, height),
      rotation: 0,
      z: 1,
      createdAt: 1,
      data: data(font).toJson(),
    );
  }

  test('a box in a missing font is fitted into its frame; others are not', () {
    final e = box(missing);
    expect(TextLayout.heightOf(TextData.fromJson(e.data), 120), greaterThan(e.rect.height + 1));
    final shown = ShownTextLayout.of(TextData.fromJson(e.data), e.rect.size);
    addTearDown(shown.dispose);
    expect(shown.scale, lessThan(1));
    expect(shown.layout.height * shown.scale, lessThanOrEqualTo(e.rect.height + 0.01));
    expect(shown.layout.painter.width * shown.scale, lessThanOrEqualTo(e.rect.width + 0.01));
    // The data keeps its font.
    expect(TextData.fromJson(e.data).font, missing);

    final own = box(TextFont.caveat);
    final fits = ShownTextLayout.of(TextData.fromJson(own.data), own.rect.size);
    addTearDown(fits.dispose);
    expect(fits.scale, 1);
  });

  test('drawn, the text of a missing font stays above its frame\'s bottom', () async {
    final e = box(missing);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ElementRenderer.draw(canvas, e);
    const size = 400;
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = (await image.toByteData())!;
    var inkBelow = 0, inkInside = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (bytes.getUint8((y * size + x) * 4 + 3) == 0) continue;
        if (y >= e.rect.bottom.ceil() || x >= e.rect.right.ceil()) {
          inkBelow++;
        } else {
          inkInside++;
        }
      }
    }
    expect(inkInside, greaterThan(0));
    expect(inkBelow, 0);
  });

  test('a fitted box\'s checkboxes are hit where they are drawn', () {
    final paras = List.filled(1, const ParaStyle(list: ListKind.check));
    final e = box(missing, paras: paras);
    final shown = ShownTextLayout.of(TextData.fromJson(e.data), e.rect.size);
    addTearDown(shown.dispose);
    expect(shown.scale, lessThan(1));
    final drawn = shown.layout.markerBoxes.single.center * shown.scale;
    expect(TextHitTest.checkboxAt(e, e.rect.topLeft + drawn), 0);
  });
}
