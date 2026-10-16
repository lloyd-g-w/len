/// Prints exported PDFs (UX_AUDIT R22-8) without a printing package:
/// `printPdf` hands the file to Android's print framework (`PrintPlugin.kt`),
/// to the default PDF reader's print verb on Windows (else opens it there),
/// to the default viewer on Linux (to print from there) and to the browser's
/// print dialog on the web. Results are [PrintHandoff]s
/// (`print_document_api.dart`).
library;

export 'print_document_api.dart';
export 'print_document_native.dart' if (dart.library.js_interop) 'print_document_web.dart';
