import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/file_names.dart';
import '../../../data/archive/len_archives.dart';
import '../../../domain/folder.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../platform/file_export.dart' as platform;
import '../../backup/len_file_flows.dart';
import '../progress_dialog.dart';
import 'export_flow.dart';
import 'export_messages.dart';
import 'export_options.dart';
import 'export_report.dart';
import 'export_sheet.dart';
import 'notebook_exporter.dart';

/// Exports whole [notebooks] from the library (UX_AUDIT R7-8), or those of
/// [folder] (its "Export…"). One notebook opens the editor's export sheet
/// with all its pages (a canvas, the canvas sheet); several, or a folder,
/// ask once (format, what to include, no page range) and give one PDF per
/// notebook (or its pages as PNGs), saved or shared together, or one Len
/// file holding them all (a folder's keeps its subfolders). [exporter] and
/// [save] are for tests.
Future<void> exportNotebooks(
  BuildContext context,
  List<Notebook> notebooks, {
  Folder? folder,
  NotebookExporter? exporter,
  ExportSaver save = platform.saveOrShareAll,
  @visibleForTesting LenExport lenExport = exportLenFlow,
}) async {
  if (notebooks.isEmpty) {
    if (folder != null) showMessage(context, 'Nothing to export yet: the folder is empty');
    return;
  }
  final services = AppScope.read(context);
  if (notebooks.length == 1 && folder == null) {
    final notebook = notebooks.single;
    if (notebook.kind == NotebookKind.canvas) {
      return exportCanvasFlow(context, notebook: notebook, exporter: exporter, save: save);
    }
    final pages = services.pages.pagesOf(notebook.id);
    if (pages.isEmpty) return showMessage(context, 'Nothing to export yet: no pages');
    return exportFlow(
      context,
      notebook: notebook,
      pages: pages,
      currentPage: 0,
      // No page is being read here: all pages, whatever the editor's last.
      resumeRange: false,
      exporter: exporter,
      save: save,
    );
  }
  final worker = exporter ?? NotebookExporter(services);
  final count = '${notebooks.length} ${notebooks.length == 1 ? 'notebook' : 'notebooks'}';
  final len = folder == null
      ? (scope: LenScope.notebooks([for (final n in notebooks) n.id]), title: count, whole: count)
      : (scope: LenScope.folder(folder.id), title: folder.name, whole: 'Whole folder');
  try {
    await _exportSeveral(context, services, notebooks, count, worker, save, len, lenExport);
  } finally {
    if (exporter == null) await worker.dispose();
  }
}

Future<void> _exportSeveral(
  BuildContext context,
  AppServices services,
  List<Notebook> notebooks,
  String subject,
  NotebookExporter worker,
  ExportSaver save,
  ({LenScope scope, String title, String whole}) len,
  LenExport lenExport,
) async {
  // The sheet sees every page, for its count and whether any has a PDF
  // background; an empty canvas has nothing to give.
  List<NotebookPage> pagesOf(Notebook n, {bool template = true}) => n.kind == NotebookKind.canvas
      ? [?worker.canvasPage(n, template: template)?.page]
      : services.pages.pagesOf(n.id);
  final all = [for (final n in notebooks) ...pagesOf(n)];
  if (all.isEmpty) return showMessage(context, 'Nothing to export yet: no pages');
  final options = await showExportSheet(
    context,
    title: len.title,
    pages: all,
    currentPage: 0,
    choosePages: false,
    whole: len.whole,
  );
  if (options == null || !context.mounted) return;
  if (options.format == ExportFormat.len) {
    // One file: the notebooks (or the folder) as they are.
    await lenExport(context, len.scope, name: lenFileName(len.title), toDevice: options.toDevice);
    return;
  }
  final report = ExportReport();
  final taken = <String>{};
  // Two notebooks of the same name (or names only differing by case) don't
  // overwrite each other.
  String unique(String name) => uniqueFileName(name, taken);

  try {
    final files = await runWithSteps(context, 'Exporting', subject: subject, cancellable: true, (
      progress,
    ) async {
      final out = <ExportFile>[];
      for (final (i, n) in notebooks.indexed) {
        progress.step(i, notebooks.length, stage: 'Rendering…', unit: 'notebook');
        out.addAll(await _filesOf(n, services, worker, options, report, unique));
      }
      progress.check(); // Cancelled while the last file was assembled.
      return out;
    });
    if (files.isEmpty || !context.mounted) return;
    final saved = await save(
      files,
      mime: options.format.mime,
      toDevice: options.toDevice,
      subject: len.title,
    );
    if (saved == null || !context.mounted) return;
    showExported(context, saved, plural: 'files', note: report.summary);
  } on Cancelled {
    return;
  } on Object catch (e, stack) {
    debugPrint('Export failed: $e\n$stack');
    if (context.mounted) showExportFailed(context, subject, e);
  }
}

/// The files of notebook [n] for [options]: one PDF, or a PNG per page.
Future<List<ExportFile>> _filesOf(
  Notebook n,
  AppServices services,
  NotebookExporter worker,
  ExportOptions options,
  ExportReport report,
  String Function(String name) unique,
) async {
  final pdf = options.format == ExportFormat.pdf;
  if (n.kind == NotebookKind.canvas) {
    final canvas = worker.canvasPage(n, template: options.includeTemplates);
    if (canvas == null) return const [];
    final bytes = pdf
        ? await worker.canvasPdf(canvas, title: n.title, report: report)
        : await worker.canvasPng(canvas, scale: pngScale, report: report);
    return [(bytes: bytes, name: unique('${safeFileName(n.title)}.${options.format.extension}'))];
  }
  final pages = [
    for (final p in services.pages.pagesOf(n.id))
      exportedPage(p, includeTemplate: options.includeTemplates),
  ];
  if (pages.isEmpty) return const [];
  final names = exportFileNames(n.title, options.format, [
    for (var i = 0; i < pages.length; i++) i,
  ], pages.length);
  if (pdf) {
    final bytes = await worker.pdf(
      pages,
      title: n.title,
      backgrounds: options.includeBackgrounds,
      report: report,
    );
    return [(bytes: bytes, name: unique(names.single))];
  }
  return [
    for (final (i, page) in pages.indexed)
      (
        bytes: await worker.png(
          page,
          scale: pngScale,
          backgrounds: options.includeBackgrounds,
          report: report,
        ),
        name: unique(names[i]),
      ),
  ];
}
