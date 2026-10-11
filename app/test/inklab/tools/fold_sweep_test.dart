import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/render/ribbon_emitter.dart';
import 'package:len/ink/render/stroke_outline.dart';

import '../../ribbon_exactness_test.dart' as ex;

void main() {
  test('sweep', () {
    for (final adv in [0.25, 0.0, -1.0, -3.0, -1e9]) {
      RibbonEmitter.foldAdvance = adv;
      var worst = 0;
      for (final width in [2.5, 8.0, 16.0, 30.0]) {
        for (final st in [0.0, 1.0]) {
          final spec = OutlineSpec(width: width, thinning: 0.6, streamline: st);
          for (final p in ex.strokes(width.toInt())) {
            worst = math.max(worst, ex.holes(p, spec, zoom: 8));
          }
        }
      }
      // ignore: avoid_print
      print('adv $adv: worst $worst');
    }
  });
}
