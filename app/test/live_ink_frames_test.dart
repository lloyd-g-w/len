// The live stroke never flickers between frames: rendered frame by frame
// as the editor's live layer draws it (frozen pieces and a rebuilt tail),
// no frame loses ink the frame before showed, except right at the tip
// (where the newest samples may still move the line), for every
// stabiliser, end style, zoom and device-pixel ratio, however the samples
// are batched into frames; and the pen-up frame keeps all of it but the
// very end.

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';

import 'support/handwriting.dart';
import 'support/ink_frames.dart';
import 'support/ink_scene.dart';

void main() {
  final words = [
    Handwriting(seed: 3).cursive(const Offset(20, 60), [e, l, u, e, l, l, e]),
    Handwriting(seed: 9, jitter: 0.3).cursive(const Offset(30, 50), [u, l, e, e, u, l]),
  ];

  for (final streamline in [0.0, 0.3, 1.0]) {
    for (final ends in StrokeEnds.values) {
      // The tablet's ratio for every end; the others with round ends.
      final views = ends == StrokeEnds.round
          ? [(1.0, 1.0), (2.5, 2.625), (0.6, 1.5)]
          : [(2.5, 2.625)];
      for (final (scale, dpr) in views) {
        final name = 'stabiliser $streamline, ${ends.name} ends, ${scale * 100} %, ${dpr}x';
        testWidgets('live ink loses nothing behind the tip, nor at pen-up ($name)', (tester) async {
          await tester.runAsync(() async {
            final scene = InkScene(const [], scale: scale, dpr: dpr);
            final f = InkFrames(
              size: scene.size,
              dpr: dpr,
              viewport: scene.viewport,
              paintInk: (canvas) => scene.painter().paint(canvas, scene.size),
            );
            for (final (w, word) in words.indexed) {
              // Samples batched unevenly into frames (coalesced events).
              final batches = [1, 3, 2, 7, 1, 4];
              var n = 0, b = 0;
              final tips = <Offset>[];
              final frames = <Frame>[];
              f.live.begin(
                tool: InkTool.ballpoint,
                color: 0xFF1B1F3B,
                width: 2.5,
                style: StrokeStyle(
                  thinning: 0.3,
                  streamline: streamline,
                  unit: 1 / scale,
                  ends: ends,
                ).copyWith(taperStart: ends == StrokeEnds.tapered ? 6 : null),
              );
              while (n < word.length) {
                final take = batches[b++ % batches.length];
                f.live.addAll(word.sublist(n, (n + take).clamp(0, word.length)));
                n += take;
                tips.add(word[(n - 1).clamp(0, word.length - 1)].offset);
                frames.add(await f.frame());
              }
              // Near the tip the newest samples still shape the line. And a
              // flat-ended stroke starts as a square under the nib (its way
              // unknown yet) that turns into a flat cap across it.
              final reach = 6 * scale;
              final start = [
                if (ends == StrokeEnds.flat) f.around(word.first.offset, (2.5 + 2) * scale),
              ];
              for (var k = 1; k < frames.length; k++) {
                final lost = lostInk(
                  frames[k - 1],
                  frames[k],
                  except: [...start, f.around(tips[k - 1], reach), f.around(tips[k], reach)],
                );
                expect(lost, 0, reason: 'word $w, frame $k lost $lost px behind the tip');
              }
              final last = frames.last;
              f.lift(scene.model, id: 'w$w');
              final after = await f.frame();
              final lost = lostInk(
                last,
                after,
                except: [...start, f.around(word.last.offset, reach)],
              );
              expect(lost, 0, reason: 'word $w: pen-up lost $lost px');
            }
            scene.dispose();
          });
        });
      }
    }
  }
}
