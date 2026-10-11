import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/replay_run.dart';

import '../metrics/overlay_metrics.dart';
import '../metrics/raster.dart';
import '../sim/cases.dart';

void main() {
  test('debug overlay', () {
    final c = simCases.firstWhere((c) => c.name == const String.fromEnvironment('CASE'));
    final rec = c.record(defaultPen.copyWith(streamline: 0.4));
    final r = ReplayResult.run(rec.recording);
    final ms = overlayMoments(r);
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      final b = m.window;
      final f = Coverage.around(b)..fill(m.flutter);
      final o = Coverage.around(b)..fill(m.overlay);
      final ref = Coverage.around(b)..fill(m.reference);
      var gaps = <String>[];
      for (var y = b.top.floor(); y <= b.bottom.ceil(); y++) {
        for (var x = b.left.floor(); x <= b.right.ceil(); x++) {
          final cr = ref.at(x, y), cf = f.at(x, y), co = o.at(x, y);
          if (cr - math.max(cf, co) > 0.5) gaps.add('($x,$y)');
        }
      }
      if (gaps.isNotEmpty) {
        // ignore: avoid_print
        print(
          'moment $i/${ms.length} overlay contours ${m.overlay.length} bounds ${boundsOf(m.overlay)} gaps $gaps ref ${boundsOf(m.reference)} flutter ${boundsOf(m.flutter)}',
        );
      }
    }
  });
}
