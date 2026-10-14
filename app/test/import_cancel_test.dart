import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/domain/cancellation.dart';
import 'package:len/features/documents/pdf/pdf_import.dart';
import 'package:len/features/documents/pdf/pdf_renderer.dart';

import 'support/real_async.dart';
import 'ui_library_test.dart' show pumpLibrary;

/// Cancelling imports (UX_AUDIT R10-18): a huge PDF while PDFium measures
/// its pages, and a batch of dropped files as a whole.
void main() {
  test('a token cancels work that cannot check by itself, at once', () async {
    final token = CancellationToken();
    final never = Completer<int>();
    final raced = token.race(never.future);
    token.cancel();
    await expectLater(raced, throwsA(isA<Cancelled>()));
    expect(() => token.race(Future.value(1)), throwsA(isA<Cancelled>()));
    expect(await CancellationToken().race(Future.value(2)), 2);
  });

  test('a PDF being measured stops on Cancel', () async {
    final services = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(services.dispose);
    final measuring = Completer<List<Size>>();
    final importer = PdfImporter(services, renderer: _Measuring(services, measuring.future));
    final token = CancellationToken();
    final creating = importer.createNotebook('sha', title: 'Huge', cover: 0, cancel: token);
    token.cancel();
    await expectLater(creating, throwsA(isA<Cancelled>()));
    measuring.complete(const [Size(612, 792)]);
    expect(services.notebooks.list(), isEmpty);
  });

  testWidgets('Cancel stops a batch of dropped PDFs', (tester) async {
    final services = await pumpLibrary(tester);
    final gate = Completer<void>();
    services.incomingFiles.add([_SlowPdf('first.pdf', gate), _SlowPdf('second.pdf', null)]);
    await pumpUntil(tester, () => find.text('first.pdf').evaluate().isNotEmpty);
    expect(find.text('Copying file…'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    gate.complete();
    await pumpUntil(tester, () => find.text('first.pdf').evaluate().isEmpty);
    // The next file's dialog would open straight away; give it the chance.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.textContaining('second.pdf'), findsNothing);
    expect(services.notebooks.list(), isEmpty);
    expect(services.blobs.pendingUploads(), isEmpty);
  });
}

/// A renderer whose page measuring ends when [sizes] does.
class _Measuring extends PdfRenderer {
  _Measuring(AppServices services, this.sizes) : super(services.blobs);

  final Future<List<Size>> sizes;

  @override
  Future<List<Size>> pageSizes(String sha) => sizes;
}

/// A dropped PDF whose second chunk arrives once [gate] completes (a big
/// file being copied).
class _SlowPdf extends XFile {
  _SlowPdf(String name, this.gate)
    : super.fromData(Uint8List.fromList('%PDF-1.7'.codeUnits), path: '/tmp/$name');

  final Completer<void>? gate;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.fromList('%PDF-1.7'.codeUnits);
    await gate?.future;
    yield Uint8List.fromList(' more'.codeUnits);
  }
}
