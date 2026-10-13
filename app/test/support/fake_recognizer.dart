import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';

/// A recogniser for tests: each stroke "spells" the word given for its id
/// in [words] (`?` if none); a group of strokes reads as their words from
/// left to right, separated by spaces. The second candidate is the same in
/// capitals.
class FakeRecognizer extends HandwritingRecognizer {
  FakeRecognizer({Map<String, String>? words, this.downloaded = true, this.supported = true})
    : words = words ?? {};

  final Map<String, String> words;
  bool downloaded;
  bool supported;

  /// Stroke ids of every recognition request, in order.
  final requests = <List<String>>[];
  final languages = <String>[];
  int downloads = 0;

  /// How many of the next recognition requests fail.
  int failures = 0;

  @override
  bool get isSupported => supported;

  @override
  String get unsupportedReason => 'Not here';

  @override
  Future<bool> isModelDownloaded(String language) async => downloaded;

  @override
  Future<void> downloadModel(String language, {required bool wifiOnly}) async {
    downloads++;
    downloaded = true;
  }

  @override
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) async {
    if (!downloaded) throw StateError('model missing');
    if (failures > 0) {
      failures--;
      throw StateError('recognition failed');
    }
    requests.add([for (final s in strokes) s.id]);
    languages.add(language);
    final ordered = [...strokes]..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    final text = ordered.map((s) => words[s.id] ?? '?').join(' ');
    return [RecognitionCandidate(text, score: 1), RecognitionCandidate(text.toUpperCase())];
  }
}

/// A zigzag stroke filling [box] (a "word"), written at [createdAt].
Stroke scribble(
  String id,
  String surface,
  Rect box, {
  int createdAt = 1,
  InkTool tool = InkTool.ballpoint,
  int color = 0xFF1F2937,
}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: tool,
  color: color,
  width: 2,
  points: [
    for (var i = 0; i <= 12; i++)
      StrokePoint(box.left + box.width * i / 12, i.isEven ? box.bottom : box.top, 0.5),
  ],
  createdAt: createdAt,
);
