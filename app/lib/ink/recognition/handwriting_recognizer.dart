import 'dart:ui';

import '../../domain/stroke.dart';

/// One reading of some handwriting, best first in a list.
class RecognitionCandidate {
  const RecognitionCandidate(this.text, {this.score});

  final String text;

  /// Engine-specific confidence; lower is better (null if not provided).
  final double? score;

  @override
  String toString() => 'RecognitionCandidate("$text", $score)';
}

/// Whether a language's recognition model is on this device.
enum ModelStatus {
  /// Not known yet (being checked).
  unknown,
  missing,
  downloading,
  downloaded,
}

/// Recognises handwriting (strokes in world coordinates) as text.
///
/// Implementations: ML Kit Digital Ink on Android
/// (`platform/handwriting_recognizer_native.dart`), [UnavailableRecognizer]
/// everywhere else, fakes in tests. Recognition runs on-device; models are
/// downloaded per language (BCP 47 tags, see `RecognitionLanguages`).
abstract class HandwritingRecognizer {
  /// Whether this platform can recognise handwriting at all.
  bool get isSupported;

  /// Why [isSupported] is false, for tooltips and settings.
  String get unsupportedReason => 'Handwriting recognition is not available on this device.';

  /// Whether the model for [language] is downloaded.
  Future<bool> isModelDownloaded(String language);

  /// Downloads the model for [language]; with [wifiOnly] the download waits
  /// for an unmetered network. Completes when it is on the device; throws
  /// if the download fails.
  Future<void> downloadModel(String language, {required bool wifiOnly});

  /// Candidate readings of [strokes] (in writing order), best first.
  /// [writingArea] (the size of the area written in) and [preContext] (the
  /// text just before) improve accuracy. Throws if the model is missing.
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  });

  /// Releases engine resources.
  void dispose() {}
}

/// The recogniser of platforms without one (Linux, Windows, web for now):
/// reports itself unsupported and recognises nothing.
class UnavailableRecognizer extends HandwritingRecognizer {
  UnavailableRecognizer([this._reason]);

  final String? _reason;

  @override
  bool get isSupported => false;

  @override
  String get unsupportedReason => _reason ?? super.unsupportedReason;

  @override
  Future<bool> isModelDownloaded(String language) async => false;

  @override
  Future<void> downloadModel(String language, {required bool wifiOnly}) =>
      Future.error(UnsupportedError(unsupportedReason));

  @override
  Future<List<RecognitionCandidate>> recognize(
    List<Stroke> strokes, {
    required String language,
    Size? writingArea,
    String preContext = '',
  }) async => const [];
}
