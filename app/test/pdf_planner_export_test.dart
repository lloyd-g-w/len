import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/export/notebook_exporter.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_test.dart' show pdfium;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync().path;
    Pdfrx.pdfiumModulePath = pdfium;
  });

  /// A PDF of planner pages in [calendar].
  Future<List<int>> export(List<Paper> papers) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final nb = services.notebooks.create(
      title: 'Planner',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
      papers: papers,
    );
    final exporter = NotebookExporter(services);
    final bytes = await exporter.pdf(services.pages.pagesOf(nb.id));
    await exporter.dispose();
    return bytes;
  }

  test('Russian and Greek planner labels are written in the embedded Inter', () async {
    const ru = PlannerCalendar(language: PlannerLanguage.ru);
    const el = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.el);
    final bytes = await export([
      Paper.planner(PaperStyle.monthlyCalendar, DateTime.utc(2026, 10), calendar: ru),
      Paper.planner(PaperStyle.yearlyOverview, DateTime.utc(2026), calendar: el),
    ]);
    final raw = String.fromCharCodes(bytes);
    // Embedded TrueType faces (regular and bold) with a ToUnicode map; no
    // standard Type 1 font (Latin-1 only) is used for labels.
    final files = {for (final m in RegExp(r'/FontFile2 (\d+) 0 R').allMatches(raw)) m[1]};
    expect(files, hasLength(2));
    expect(raw, contains('/ToUnicode'));
    expect(raw, isNot(contains('/Helvetica')));
  });

  test(
    'planner labels can be found as text in the PDF',
    skip: pdfium == null ? 'PDFium not built yet (run `flutter build linux` once)' : false,
    () async {
      const ru = PlannerCalendar(language: PlannerLanguage.ru);
      const el = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.el);
      final bytes = await export([
        Paper.planner(PaperStyle.monthlyCalendar, DateTime.utc(2026, 10), calendar: ru),
        Paper.planner(PaperStyle.yearlyOverview, DateTime.utc(2026), calendar: el),
      ]);
      final doc = await PdfDocument.openData(Uint8List.fromList(bytes));
      final month = (await doc.pages[0].loadText())!.fullText;
      expect(month, contains('Октябрь'));
      expect(month, contains('ПН'));
      final year = (await doc.pages[1].loadText())!.fullText;
      expect(year, contains('Ιανουάριος'));
      expect(year, contains('Δεκέμβριος'));
      await doc.dispose();
    },
  );
}
