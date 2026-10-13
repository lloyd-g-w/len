import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/pdf/pdf_open_failure.dart';
import 'package:pdfrx/pdfrx.dart' show PdfPasswordException;

/// UX_AUDIT P2-31: a password-protected PDF is told apart from a damaged one.
void main() {
  test('password-protected and damaged PDFs are told apart', () {
    expect(
      pdfOpenFailure('scan.pdf', const PdfPasswordException('No password supplied')),
      'Couldn’t open “scan.pdf”: it’s password-protected',
    );
    expect(
      pdfOpenFailure('scan.pdf', const FormatException('bad xref')),
      'Couldn’t open “scan.pdf”: it may be damaged, or not a PDF',
    );
  });
}
