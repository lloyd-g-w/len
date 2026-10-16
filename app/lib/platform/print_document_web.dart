import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_export_web.dart' show downloadBlob;
import 'print_document_api.dart';

/// The browser's print dialog speaks for itself.
String? get printNote => null;

/// The hidden frame holding the PDF last printed, and its blob URL: kept
/// until the next print (removing it early can end the print dialog).
web.HTMLIFrameElement? _frame;
String? _frameUrl;

/// Prints the PDF [bytes] through the browser: in a hidden frame whose
/// print dialog opens over Len where the browser shows PDFs itself, else
/// in a new tab (to print from there), else (a blocked tab) downloaded.
/// [pages] is unused here.
Future<PrintHandoff> printPdf(Uint8List bytes, {required String name, required int pages}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
  if (web.window.navigator.pdfViewerEnabled) {
    try {
      await _printInFrame(blob);
      return PrintHandoff.dialog;
    } on Object catch (e) {
      // Some browsers refuse to print a PDF frame: try a tab.
      web.console.warn('Printing in a frame failed: $e'.toJS);
    }
  }
  final url = web.URL.createObjectURL(blob);
  if (web.window.open(url, '_blank') != null) {
    Timer(const Duration(minutes: 10), () => web.URL.revokeObjectURL(url));
    return PrintHandoff.viewer;
  }
  web.URL.revokeObjectURL(url);
  downloadBlob(blob, name: name);
  return PrintHandoff.downloaded;
}

/// Loads [blob] into a hidden frame and opens its print dialog.
Future<void> _printInFrame(web.Blob blob) async {
  _frame?.remove();
  if (_frameUrl case final url?) web.URL.revokeObjectURL(url);
  final url = _frameUrl = web.URL.createObjectURL(blob);
  // Not display: none: browsers may not load a PDF viewer there.
  final frame = _frame = web.HTMLIFrameElement()
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.border = '0'
    ..style.opacity = '0'
    ..style.pointerEvents = 'none'
    ..setAttribute('aria-hidden', 'true');
  final loaded = Completer<void>();
  frame.onload = (web.Event _) {
    if (!loaded.isCompleted) loaded.complete();
  }.toJS;
  frame.src = url;
  web.document.body!.append(frame);
  await loaded.future.timeout(const Duration(seconds: 20));
  final window = frame.contentWindow ?? (throw StateError('The PDF frame has no window'));
  window.focus();
  window.print();
}
