/// The platform's handwriting recogniser (`createHandwritingRecognizer`):
/// ML Kit Digital Ink on Android, none elsewhere (yet).
library;

export 'handwriting_recognizer_native.dart'
    if (dart.library.js_interop) 'handwriting_recognizer_web.dart';
