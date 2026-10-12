import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../domain/stroke.dart';
import '../ink/recognition/handwriting_recognizer.dart';

/// ML Kit Digital Ink Recognition on Android; unavailable on desktops.
HandwritingRecognizer createHandwritingRecognizer() => Platform.isAndroid
    ? MlKitRecognizer()
    : UnavailableRecognizer('Handwriting recognition is only available on Android for now.');

/// On-device recognition with Google ML Kit Digital Ink (one model per
/// language, downloaded on request).
///
/// Models are managed by `google_mlkit_digital_ink_recognition`; recognition
/// goes through Len's own channel (`HandwritingRecognitionPlugin.kt`), which
/// decodes, recognises and answers on background threads: the plugin's
/// channel did all but the recognition itself on the platform thread, which
/// is the UI thread on Android (≈ 40 ms a line). Points travel packed in
/// typed arrays (see [pack]).
class MlKitRecognizer extends HandwritingRecognizer {
  MlKitRecognizer({this.channel = const MethodChannel('len/handwriting')});

  /// Len's recognition channel (see `HandwritingRecognitionPlugin.kt`).
  final MethodChannel channel;
  final _models = mlkit.DigitalInkRecognizerModelManager();
  bool _used = false;

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
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) async {
    if (strokes.isEmpty) return const [];
    _used = true;
    final area = writingArea;
    final hasArea = area != null && !area.isEmpty;
    final result = await channel.invokeListMethod<Object?>('recognize', {
      'language': language,
      ...pack(strokes),
      'preContext': preContext,
      'width': hasArea ? area.width : null,
      'height': hasArea ? area.height : null,
    });
    return [
      for (final c in result ?? const <Object?>[])
        if (c case {'text': final String text, 'score': final num score})
          RecognitionCandidate(text, score: score.toDouble()),
    ];
  }

  /// The channel arguments for [strokes]: `xs`, `ys` (float32), `ts`
  /// (int64, ms; synthesised, monotonic) and `ends` (each stroke's end
  /// index into the point arrays).
  static Map<String, Object> pack(List<Stroke> strokes) {
    final count = strokes.fold(0, (n, s) => n + s.points.length);
    final xs = Float32List(count);
    final ys = Float32List(count);
    final ts = Int64List(count);
    final ends = Int32List(strokes.length);
    var t = 0;
    var i = 0;
    for (var k = 0; k < strokes.length; k++) {
      final s = strokes[k];
      // Each stroke starts at its creation time, or right after the
      // previous one if that was synthesised past it.
      t = math.max(t + _sampleMs, s.createdAt);
      for (final p in s.points) {
        xs[i] = p.x;
        ys[i] = p.y;
        ts[i] = t;
        t += _sampleMs;
        i++;
      }
      ends[k] = i;
    }
    return {'xs': xs, 'ys': ys, 'ts': ts, 'ends': ends};
  }

  @override
  void dispose() {
    if (_used) channel.invokeMethod<void>('close').ignore();
  }
}
