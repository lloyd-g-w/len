import '../ink/recognition/handwriting_recognizer.dart';

/// Browsers have no on-device recogniser Len can use.
HandwritingRecognizer createHandwritingRecognizer() =>
    UnavailableRecognizer('Handwriting recognition is not available in the browser yet.');
