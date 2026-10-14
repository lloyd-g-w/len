import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/stroke_wire.dart';

void main() {
  test('packing keeps everything an outline needs', () {
    const style = StrokeStyle(
      opacity: 0.5,
      thinning: 0.3,
      streamline: 0.2,
      unit: 0.25,
      ends: StrokeEnds.flat,
      taperStart: 4,
      taperEnd: 6,
      startPhase: 0.75,
      cutEnd: true,
    );
    final strokes = [
      Stroke(
        id: 'a',
        surfaceId: 's',
        tool: InkTool.highlighter,
        color: 0xff112233,
        width: 7,
        style: style,
        createdAt: 1,
        points: const [StrokePoint(1, 2, 0.5), StrokePoint(3, 4, 0.75)],
      ),
      Stroke(
        id: 'b',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0,
        width: 2,
        createdAt: 2,
        points: const [StrokePoint(5, 6, 1)],
      ),
    ];

    final back = StrokeWire.unpack(StrokeWire.pack(strokes));

    expect(back, hasLength(2));
    for (var i = 0; i < 2; i++) {
      expect(back[i].tool, strokes[i].tool);
      expect(back[i].width, strokes[i].width);
      expect(back[i].style, strokes[i].style);
      expect(
        [for (final p in back[i].points) (p.x, p.y, p.pressure)],
        [for (final p in strokes[i].points) (p.x, p.y, p.pressure)],
      );
    }
  });
}
