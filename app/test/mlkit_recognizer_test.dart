import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/platform/handwriting_recognizer_native.dart';

Stroke _stroke(String id, int createdAt, List<StrokePoint> points) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xff000000,
  width: 2,
  points: points,
  createdAt: createdAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('len/handwriting');
  final strokes = [
    _stroke('a', 1000, const [StrokePoint(1, 2, 1), StrokePoint(3, 4, 1)]),
    // Written "before" the end of the previous stroke's synthesised time.
    _stroke('b', 1005, const [StrokePoint(5, 6, 1)]),
  ];

  test('pack sends typed arrays with monotonic timestamps and stroke ends', () {
    final packed = MlKitRecognizer.pack(strokes);
    expect(packed['xs'], Float32List.fromList([1, 3, 5]));
    expect(packed['ys'], Float32List.fromList([2, 4, 6]));
    expect(packed['ts'], Int64List.fromList([1000, 1008, 1024]));
    expect(packed['ends'], Int32List.fromList([2, 3]));
  });

  test('recognize goes through len/handwriting and reads the candidates', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return [
        {'text': 'hello', 'score': 0.5},
        {'text': 'hullo', 'score': 1},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final recognizer = MlKitRecognizer();
    final candidates = await recognizer.recognize(
      strokes,
      language: 'en-US',
      writingArea: const Size(100, 30),
      preContext: 'say',
    );
    expect(candidates.map((c) => (c.text, c.score)), [('hello', 0.5), ('hullo', 1.0)]);
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(calls.single.method, 'recognize');
    expect(args['language'], 'en-US');
    expect(args['preContext'], 'say');
    expect((args['width'], args['height']), (100.0, 30.0));
    expect(args['ends'], Int32List.fromList([2, 3]));

    recognizer.dispose();
    expect(calls.last.method, 'close');
  });
}
