import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/archive/len_archives.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../platform/file_export.dart' as platform;
import '../../backup/len_file_flows.dart';
import '../progress_dialog.dart';
import 'export_messages.dart';
import 'export_options.dart';
import 'export_report.dart';
import 'export_sheet.dart';
import 'notebook_exporter.dart';

export 'export_options.dart' show ExportRange;

/// An exported file.
typedef ExportFile = ({Uint8List bytes, String name});

/// Hands exported [files] to the user and returns where they went (null
/// if cancelled); `saveOrShareAll` from `platform/file_export`. With
/// [toDevice] (Android) through the system's save dialog instead of the
/// share sheet.
typedef ExportSaver = Future<platform.ExportedFiles?> Function(
  List<ExportFile> files, {
  required String mime,
  bool toDevice,
});

/// Asks what to export from [pages] of [notebook] (the export sheet,
/// starting at [initialRange], or at [initialPages] as a page range;
/// [currentPage] is zero-based), exports with
/// a progress dialog and lets the user save (desktop), share (mobile) or
/// download (web) the file(s). [exporter] and [save] are for tests.
Future<void> exportFlow(
  BuildContext context, {
  required Notebook notebook,
  required List<NotebookPage> pages,
  required int currentPage,
  ExportRange initialRange = ExportRange.all,
  List<int>? initialPages,
  NotebookExporter? exporter,
  ExportSaver save = platform.saveOrShareAll,
}) async {
  final options = await showExportSheet(
    context,
    title: notebook.title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
    initialPages: initialPages,
  );
  if (options == null || !context.mounted) return;
  await runExport(
    context,
    options,
    notebook: notebook,
    pages: pages,
    exporter: exporter,
    save: save,
  );
}

/// Exports [options] from [pages] of [notebook] behind a progress dialog,
/// then saves or shares the result.
Future<void> runExport(
  BuildContext context,
  ExportOptions options, {
  required Notebook notebook,
  required List<NotebookPage> pages,
  NotebookExporter? exporter,
  ExportSaver save = platform.saveOrShareAll,
}) async {
  if (options.format == ExportFormat.len) {
    await exportLenFlow(
      context,
      LenScope.notebook(notebook.id),
      name: lenFileName(notebook.title),
      toDevice: options.toDevice,
    );
    return;
  }
  final selected = options.resolve(pages);
  if (selected.isEmpty) return;
  final names = exportFileNames(notebook.title, options.format, options.pages, pages.length);
  final worker = exporter ?? NotebookExporter(AppScope.read(context));
  final subject = names.length == 1 ? names.single : '${names.length} images';
  final report = ExportReport();
  try {
    final files = await runWithSteps(context, 'Exporting', subject: subject, cancellable: true, (
      progress,
    ) async {
      progress.stageStarted('Rendering…');
      if (options.format == ExportFormat.pdf) {
        final bytes = await worker.pdf(
          selected,
          title: notebook.title,
          backgrounds: options.includeBackgrounds,
          report: report,
          onProgress: (stage, done, total) => progress.step(
            done,
            total,
            stage: stage == ExportStage.preparing ? 'Preparing pages…' : 'Writing PDF…',
          ),
        );
        progress.check(); // Cancelled while the file was assembled.
        return [(bytes: bytes, name: names.single)];
      }
      final pngs = [
        for (final (i, page) in selected.indexed)
          (
            bytes: await _png(
              worker,
              page,
              options,
              report,
              () => progress.step(i, selected.length),
            ),
            name: names[i],
          ),
      ];
      progress.check();
      return pngs;
    });
    if (!context.mounted) return;
    final saved = await save(files, mime: options.format.mime, toDevice: options.toDevice);
    if (saved == null || !context.mounted) return;
    showExported(context, saved, plural: 'images', note: report.summary);
  } on Cancelled {
    return; // Nothing was saved; rendered pages are already disposed.
  } on Object catch (e, stack) {
    // Errors too: the dialog is closed, the user must hear about it.
    debugPrint('Export failed: $e\n$stack');
    if (context.mounted) showExportFailed(context, _quoted(subject, names.length), e);
  } finally {
    if (exporter == null) await worker.dispose();
  }
}

/// "“Lecture.pdf”" for one file, "3 images" for several.
String _quoted(String subject, int count) => count == 1 ? '“$subject”' : subject;

Future<Uint8List> _png(
  NotebookExporter exporter,
  NotebookPage page,
  ExportOptions options,
  ExportReport report,
  VoidCallback started,
) {
  started();
  return exporter.png(
    page,
    scale: pngScale,
    backgrounds: options.includeBackgrounds,
    report: report,
  );
}

/// Exports infinite canvas [notebook]: its whole drawing as one PDF page or
/// PNG, sized to fit it (UX_AUDIT #25). Asks for the format and whether to
/// draw the canvas's background, then saves or shares like [exportFlow].
/// An empty canvas says so instead.
Future<void> exportCanvasFlow(
  BuildContext context, {
  required Notebook notebook,
  NotebookExporter? exporter,
  ExportSaver save = platform.saveOrShareAll,
}) async {
  final worker = exporter ?? NotebookExporter(AppScope.read(context));
  final report = ExportReport();
  try {
    final preview = worker.canvasPage(notebook);
    if (preview == null) {
      showMessage(context, 'Nothing to export yet: the canvas is empty');
      return;
    }
    final options = await showExportSheet(
      context,
      title: notebook.title,
      pages: [preview.page],
      currentPage: 0,
      canvas: true,
    );
    if (options == null || !context.mounted) return;
    if (options.format == ExportFormat.len) {
      await exportLenFlow(
        context,
        LenScope.notebook(notebook.id),
        name: lenFileName(notebook.title),
        toDevice: options.toDevice,
      );
      return;
    }
    final name = '${safeFileName(notebook.title)}.${options.format.extension}';
    final files = await runWithSteps(context, 'Exporting', subject: name, cancellable: true, (
      progress,
    ) async {
      progress.stageStarted('Rendering…');
      // Again: the sheet may have been open a while (sync, another pane).
      final canvas = worker.canvasPage(notebook, template: options.includeTemplates);
      if (canvas == null) return const <ExportFile>[];
      final bytes = options.format == ExportFormat.pdf
          ? await worker.canvasPdf(canvas, title: notebook.title, report: report)
          : await worker.canvasPng(canvas, scale: pngScale, report: report);
      progress.check(); // Cancelled meanwhile.
      return [(bytes: bytes, name: name)];
    });
    if (files.isEmpty || !context.mounted) return;
    final saved = await save(files, mime: options.format.mime, toDevice: options.toDevice);
    if (saved == null || !context.mounted) return;
    showExported(context, saved, plural: 'images', note: report.summary);
  } on Cancelled {
    return;
  } on Object catch (e, stack) {
    debugPrint('Canvas export failed: $e\n$stack');
    if (context.mounted) showExportFailed(context, '“${notebook.title}”', e);
  } finally {
    if (exporter == null) await worker.dispose();
  }
}
