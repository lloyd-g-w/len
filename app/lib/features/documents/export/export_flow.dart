import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../progress_dialog.dart';
import 'notebook_exporter.dart';

/// What to export from the editor.
enum ExportKind {
  notebookPdf('Notebook as PDF'),
  pagePdf('This page as PDF'),
  pagePng('This page as PNG');

  const ExportKind(this.label);
  final String label;
}

/// Exports from [notebook] and lets the user save (desktop) or share
/// (mobile) the file.
Future<void> exportFlow(
  BuildContext context, {
  required ExportKind kind,
  required Notebook notebook,
  required List<NotebookPage> pages,
  required NotebookPage page,
}) async {
  final services = AppScope.read(context);
  final exporter = NotebookExporter(services);
  final base = _safeName(notebook.title);
  final number = pages.indexWhere((x) => x.id == page.id) + 1;
  final (name, mime) = switch (kind) {
    ExportKind.notebookPdf => ('$base.pdf', 'application/pdf'),
    ExportKind.pagePdf => ('$base p$number.pdf', 'application/pdf'),
    ExportKind.pagePng => ('$base p$number.png', 'image/png'),
  };
  try {
    final bytes = await runWithSteps(context, 'Exporting', subject: name, (progress) {
      void report(ExportStage stage, int done, int total) => progress.step(
        done,
        total,
        stage: stage == ExportStage.preparing ? 'Preparing pages…' : 'Writing PDF…',
      );
      progress.stageStarted('Rendering…');
      return switch (kind) {
        ExportKind.notebookPdf => exporter.pdf(pages, title: notebook.title, onProgress: report),
        ExportKind.pagePdf => exporter.pdf([page], title: notebook.title),
        ExportKind.pagePng => exporter.png(page),
      };
    });
    if (!context.mounted) return;
    final saved = await saveOrShare(bytes, name: name, mime: mime);
    if (saved != null && context.mounted) showMessage(context, 'Saved $saved');
  } on Exception catch (e) {
    debugPrint('Export failed: $e');
    if (context.mounted) showMessage(context, 'Export failed: $e');
  } finally {
    await exporter.dispose();
  }
}

/// Desktop: asks where to save and returns the path (null if cancelled).
/// Mobile: opens the share sheet and returns null.
Future<String?> saveOrShare(Uint8List bytes, {required String name, required String mime}) async {
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)]));
    return null;
  }
  final extension = p.extension(name).replaceFirst('.', '');
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: extension.toUpperCase(), extensions: [extension], mimeTypes: [mime]),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}

/// A file name from a notebook title.
String _safeName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
  return cleaned.isEmpty ? 'Notebook' : cleaned;
}
