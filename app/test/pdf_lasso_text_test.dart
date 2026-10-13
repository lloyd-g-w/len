import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/editor/pdf/pdf_interaction.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

import 'pdf_interaction_test.dart' show openPdfEditor, pdfTextAt;
import 'pdf_test.dart' show pdfium;

/// R7-1: with the lasso, the pen selects PDF text (a tap, a hold and drag,
/// an open drag), while loops still select ink.
void main() {
  late Directory dir;
  late AppServices services;

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('len_pdf_lasso_');
    services = AppServices.create(AppDatabase.inMemory(), blobBackend: FileBlobBackend(dir.path));
  });
  tearDown(() {
    services.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<PdfInteraction> open(WidgetTester tester) async {
    final pdf = await openPdfEditor(tester, services, dir);
    pdf.tools
      ..stylusOnly = true
      ..tool = EditorTool.lasso;
    await tester.pumpAndSettle();
    return pdf;
  }

  /// A pen drag through [points], [hold]ing still at the first one.
  Future<void> penDrag(WidgetTester tester, List<Offset> points, {Duration? hold}) async {
    final pen = await tester.startGesture(points.first, kind: PointerDeviceKind.stylus);
    if (hold != null) await tester.pump(hold);
    for (final p in points.skip(1)) {
      await pen.moveTo(p);
      await tester.pump();
    }
    await pen.up();
    await tester.pumpAndSettle();
  }

  /// Points every few pixels from [a] to [b].
  List<Offset> line(Offset a, Offset b) => [
    for (var t = 0.0; t <= 1.0001; t += 0.1) Offset.lerp(a, b, t)!,
  ];

  testWidgets('a pen tap on text selects its word, with the menu', skip: pdfium == null, (
    tester,
  ) async {
    final pdf = await open(tester);
    await tester.tapAt(pdfTextAt(pdf, 'Hello', i: 1), kind: PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(pdf.selection.text, 'Hello');
    expect(find.byKey(const ValueKey('pdf-copy')), findsOneWidget);
    // A tap off the text drops it.
    await tester.tapAt(const Offset(450, 1000), kind: PointerDeviceKind.stylus);
    await tester.pumpAndSettle();
    expect(pdf.selection.isEmpty, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pen drag along text selects what it spans', skip: pdfium == null, (tester) async {
    final pdf = await open(tester);
    await penDrag(
      tester,
      line(pdfTextAt(pdf, 'Second'), pdfTextAt(pdf, 'text', i: 3, right: true)),
    );
    expect(pdf.selection.text, 'Second line of text');
    expect(pdf.selection.showsMenu, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'holding the pen on text selects the word; dragging extends it',
    skip: pdfium == null,
    (tester) async {
      final pdf = await open(tester);
      final start = pdfTextAt(pdf, 'Hello');
      final pen = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
      await tester.pump(const Duration(milliseconds: 600));
      expect(pdf.selection.text, 'Hello', reason: 'held: the word');
      for (final p in line(start, pdfTextAt(pdf, 'PDF', i: 2, right: true))) {
        await pen.moveTo(p);
        await tester.pump();
      }
      await pen.up();
      await tester.pumpAndSettle();
      expect(pdf.selection.text, 'Hello PDF');
      expect(pdf.selection.showsMenu, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a loop that starts on text still selects the ink it circles', skip: pdfium == null, (
    tester,
  ) async {
    final pdf = await open(tester);
    // Ink written under "Visit example".
    final ink = pdfTextAt(pdf, 'Visit') + const Offset(0, 40);
    pdf.tools.tool = EditorTool.pen;
    await penDrag(tester, line(ink, ink + const Offset(80, 0)));
    pdf.tools.tool = EditorTool.lasso;
    await tester.pumpAndSettle();
    final top = pdfTextAt(pdf, 'Visit');
    await penDrag(tester, [
      top,
      top + const Offset(140, 0),
      top + const Offset(140, 70),
      top + const Offset(-20, 70),
      top + const Offset(-20, 0),
      top + const Offset(-4, 0),
    ]);
    expect(find.byTooltip('Delete (Del)'), findsOneWidget, reason: 'the ink is selected');
    expect(pdf.selection.isEmpty, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
