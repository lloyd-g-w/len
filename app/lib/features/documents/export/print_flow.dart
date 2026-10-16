import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../platform/print_document.dart' as platform;
import '../../../ui/error_details.dart';
import '../progress_dialog.dart';
import 'export_flow.dart';
import 'export_options.dart';
import 'export_report.dart';
import 'export_sheet.dart';
import 'notebook_exporter.dart';

/// Prints the PDF [bytes] of [pages] pages named [name]; where it went
/// (`printPdf` from `platform/print_document`).
typedef PdfPrinter = Future<platform.PrintHandoff> Function(
  Uint8List bytes, {
  required String name,
  required int pages,
});

/// Asks what to print from [pages] of [notebook] (the export sheet as a
/// PDF export with a Print button, UX_AUDIT R22-8; [currentPage] is
/// zero-based, [initialRange] and [resumeRange] as in [exportFlow]),
/// renders the PDF behind a progress dialog and hands it to the system's
/// printing. [exporter] and [printer] are for tests.
Future<void> printFlow(
  BuildContext context, {
  required Notebook notebook,
  required List<NotebookPage> pages,
  required int currentPage,
  ExportRange initialRange = ExportRange.all,
  bool resumeRange = true,
  NotebookExporter? exporter,
  PdfPrinter printer = platform.printPdf,
}) async {
  final options = await showExportSheet(
    context,
    title: notebook.title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
    resumeRange: resumeRange,
    print: true,
  );
  if (options == null || !context.mounted) return;
  final selected = options.resolve(pages);
  if (selected.isEmpty) return;
  final name = exportFileNames(
    notebook.title,
    ExportFormat.pdf,
    options.pages,
    pages.length,
  ).single;
  await _print(
    context,
    name: name,
    pages: selected.length,
    exporter: exporter,
    printer: printer,
    render: (worker, progress, report) => renderPdf(
      worker,
      progress,
      selected,
      title: notebook.title,
      backgrounds: options.includeBackgrounds,
      report: report,
    ),
  );
}

/// Prints infinite canvas [notebook]: its whole drawing on one page, as
/// [exportCanvasFlow] exports it. An empty canvas says so instead.
Future<void> printCanvasFlow(
  BuildContext context, {
  required Notebook notebook,
  NotebookExporter? exporter,
  PdfPrinter printer = platform.printPdf,
}) async {
  final worker = exporter ?? NotebookExporter(AppScope.read(context));
  try {
    final preview = worker.canvasPage(notebook);
    if (preview == null) {
      showMessage(context, 'Nothing to print yet: the canvas is empty');
      return;
    }
    final options = await showExportSheet(
      context,
      title: notebook.title,
      pages: [preview.page],
      currentPage: 0,
      canvas: true,
      print: true,
    );
    if (options == null || !context.mounted) return;
    await _print(
      context,
      name: '${safeFileName(notebook.title)}.pdf',
      pages: 1,
      exporter: worker,
      printer: printer,
      render: (worker, progress, report) async {
        // Again: the sheet may have been open a while (sync, another pane).
        final canvas = worker.canvasPage(notebook, template: options.includeTemplates);
        if (canvas == null) return null;
        final bytes = await worker.canvasPdf(canvas, title: notebook.title, report: report);
        progress.check();
        return bytes;
      },
    );
  } finally {
    if (exporter == null) await worker.dispose();
  }
}

/// Prints [notebook] from the library: a canvas's drawing, else the
/// sheet over all its pages.
Future<void> printNotebook(
  BuildContext context,
  Notebook notebook, {
  NotebookExporter? exporter,
  PdfPrinter printer = platform.printPdf,
}) async {
  if (notebook.kind == NotebookKind.canvas) {
    return printCanvasFlow(context, notebook: notebook, exporter: exporter, printer: printer);
  }
  final pages = AppScope.read(context).pages.pagesOf(notebook.id);
  if (pages.isEmpty) return showMessage(context, 'Nothing to print yet: no pages');
  return printFlow(
    context,
    notebook: notebook,
    pages: pages,
    currentPage: 0,
    // No page is being read here: all pages, whatever the editor's last.
    resumeRange: false,
    exporter: exporter,
    printer: printer,
  );
}

/// Renders the PDF named [name] with [render] behind a cancellable
/// progress dialog (null: nothing to print), then hands it to [printer]
/// and says where it went.
Future<void> _print(
  BuildContext context, {
  required String name,
  required int pages,
  required NotebookExporter? exporter,
  required PdfPrinter printer,
  required Future<Uint8List?> Function(
    NotebookExporter worker,
    TaskProgress progress,
    ExportReport report,
  )
  render,
}) async {
  final worker = exporter ?? NotebookExporter(AppScope.read(context));
  final report = ExportReport();
  try {
    final bytes = await runWithSteps(
      context,
      'Preparing to print',
      subject: name,
      cancellable: true,
      (progress) {
        progress.stageStarted('Rendering…');
        return render(worker, progress, report);
      },
    );
    if (bytes == null || !context.mounted) return;
    final handoff = await printer(bytes, name: name, pages: pages);
    if (context.mounted) showPrinted(context, handoff, name: name, note: report.summary);
  } on Cancelled {
    return;
  } on Object catch (e, stack) {
    debugPrint('Printing failed: $e\n$stack');
    if (context.mounted) _showPrintFailed(context, name, e);
  } finally {
    if (exporter == null) await worker.dispose();
  }
}

/// Where the PDF [name] went to be printed, when it isn't a print dialog
/// in view: "Opened “Lab.pdf” in your PDF viewer to print". [note] adds
/// what was left out (then said after a print dialog too).
@visibleForTesting
void showPrinted(
  BuildContext context,
  platform.PrintHandoff handoff, {
  required String name,
  String? note,
}) {
  final message = switch (handoff) {
    platform.PrintHandoff.dialog => note == null ? null : 'Printing “$name”',
    platform.PrintHandoff.reader => 'Sent “$name” to your PDF reader to print',
    platform.PrintHandoff.viewer => 'Opened “$name” in your PDF viewer to print',
    platform.PrintHandoff.downloaded => 'Downloaded “$name” to print from your downloads',
  };
  if (message == null) return;
  showMessage(
    context,
    note == null ? message : '$message; $note',
    duration: note == null ? null : const Duration(seconds: 8),
  );
}

/// "Couldn't print “Lab.pdf”", the error under Details.
void _showPrintFailed(BuildContext context, String name, Object error) => showMessage(
  context,
  'Couldn’t print “$name”',
  action: SnackBarAction(
    label: 'Details',
    onPressed: () =>
        unawaited(showErrorDetails(context, title: 'Printing failed', details: '$error')),
  ),
);
