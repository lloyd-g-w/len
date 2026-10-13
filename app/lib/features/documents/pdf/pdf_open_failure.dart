import 'package:pdfrx/pdfrx.dart' show PdfPasswordException;

/// What to tell the user when PDF [name] couldn't be opened because of
/// [error]: password-protected files are told apart from damaged ones (a
/// password prompt can come later).
String pdfOpenFailure(String name, Object error) => error is PdfPasswordException
    ? 'Couldn’t open “$name”: it’s password-protected'
    : 'Couldn’t open “$name”: it may be damaged, or not a PDF';
