import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../platform/file_export.dart' as platform;
import '../progress_dialog.dart';
import 'export_options.dart';
import 'export_sheet.dart';
import 'notebook_exporter.dart';

export 'export_options.dart' show ExportRange;

/// An exported file.
typedef ExportFile = ({Uint8List bytes, String name});

/// Hands exported [files] to the user and returns where they went (null
/// if cancelled or shared); `saveOrShareAll` from `platform/file_export`.
typedef ExportSaver = Future<String?> Function(List<ExportFile> files, {required String mime});

/// Asks what to export from [pages] of [notebook] (the export sheet,
/// starting at [initialRange]; [currentPage] is zero-based), exports with
/// a progress dialog and lets the user save (desktop), share (mobile) or
/// download (web) the file(s). [exporter] and [save] are for tests.
Future<void> exportFlow(
  BuildContext context, {
  required Notebook notebook,
  required List<NotebookPage> pages,
  required int currentPage,
  ExportRange initialRange = ExportRange.all,
  NotebookExporter? exporter,
  ExportSaver save = platform.saveOrShareAll,
}) async {
  final options = await showExportSheet(
    context,
    title: notebook.title,
    pages: pages,
    currentPage: currentPage,
    initialRange: initialRange,
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
  final selected = options.resolve(pages);
  if (selected.isEmpty) return;
  final names = exportFileNames(notebook.title, options.format, options.pages, pages.length);
  final worker = exporter ?? NotebookExporter(AppScope.read(context));
  final subject = names.length == 1 ? names.single : '${names.length} images';
  try {
    final files = await runWithSteps(context, 'Exporting', subject: subject, (progress) async {
      progress.stageStarted('Rendering…');
      if (options.format == ExportFormat.pdf) {
        final bytes = await worker.pdf(
          selected,
          title: notebook.title,
          backgrounds: options.includeBackgrounds,
          onProgress: (stage, done, total) => progress.step(
            done,
            total,
            stage: stage == ExportStage.preparing ? 'Preparing pages…' : 'Writing PDF…',
          ),
        );
        return [(bytes: bytes, name: names.single)];
      }
      return [
        for (final (i, page) in selected.indexed)
          (
            bytes: await _png(worker, page, options, () => progress.step(i, selected.length)),
            name: names[i],
          ),
      ];
    });
    if (!context.mounted) return;
    final saved = await save(files, mime: options.format.mime);
    if (saved == null || !context.mounted) return;
    showMessage(context, files.length == 1 ? 'Saved $saved' : 'Saved ${files.length} images');
  } on Exception catch (e) {
    debugPrint('Export failed: $e');
    if (context.mounted) showMessage(context, 'Export failed: $e');
  } finally {
    if (exporter == null) await worker.dispose();
  }
}

Future<Uint8List> _png(
  NotebookExporter exporter,
  NotebookPage page,
  ExportOptions options,
  VoidCallback started,
) {
  started();
  return exporter.png(
    page,
    scale: options.pngResolution.scale,
    backgrounds: options.includeBackgrounds,
  );
}
