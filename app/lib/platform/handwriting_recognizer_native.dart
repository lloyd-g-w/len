import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../domain/stroke.dart';
import '../ink/recognition/handwriting_recognizer.dart';

/// ML Kit Digital Ink Recognition on Android; unavailable on desktops.
HandwritingRecognizer createHandwritingRecognizer() => Platform.isAndroid
    ? MlKitRecognizer()
    : UnavailableRecognizer('Handwriting recognition is only available on Android for now.');

/// On-device recognition with Google ML Kit Digital Ink (one model per
/// language, downloaded on request; recognition runs on ML Kit's threads).
class MlKitRecognizer extends HandwritingRecognizer {
  final _models = mlkit.DigitalInkRecognizerModelManager();
  final _recognizers = <String, mlkit.DigitalInkRecognizer>{};

  /// Milliseconds between synthesised point timestamps (strokes store only
  /// their start time).
  static const int _sampleMs = 8;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelDownloaded(String language) => _models.isModelDownloaded(language);

  @override
  Future<void> downloadModel(String language, {required bool wifiOnly}) async {
    final ok = await _models.downloadModel(language, isWifiRequired: wifiOnly);
    if (!ok) throw StateError('The $language model could not be downloaded.');
  }

  @override
  Future<void> deleteModel(String language) async {
    await _recognizers.remove(language)?.close();
    await _models.deleteModel(language);
  }

  @override
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) async {
    if (strokes.isEmpty) return const [];
    final recognizer = _recognizers[language] ??= mlkit.DigitalInkRecognizer(
      languageCode: language,
    );
    final ink = mlkit.Ink();
    var t = 0;
    for (final s in strokes) {
      // Monotonic timestamps: each stroke starts at its creation time, or
      // right after the previous one if that was synthesised past it.
      t = math.max(t + _sampleMs, s.createdAt);
      final stroke = mlkit.Stroke();
      for (final p in s.points) {
        stroke.points.add(mlkit.StrokePoint(x: p.x, y: p.y, t: t));
        t += _sampleMs;
      }
      ink.strokes.add(stroke);
    }
    final area = writingArea;
    final context = mlkit.DigitalInkRecognitionContext(
      preContext: preContext.isEmpty ? null : preContext,
      writingArea: area == null || area.isEmpty
          ? null
          : mlkit.WritingArea(width: area.width, height: area.height),
    );
    final candidates = await recognizer.recognize(ink, context: context);
    return [for (final c in candidates) RecognitionCandidate(c.text, score: c.score)];
  }

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.close();
    }
    _recognizers.clear();
  }
}
