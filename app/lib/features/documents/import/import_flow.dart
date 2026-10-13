import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/archive/len_format.dart';
import '../../../domain/notebook.dart';
import '../../../domain/paper.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../backup/len_file_flows.dart';
import '../pdf/pdf_import_flow.dart';
import '../progress_dialog.dart';
import 'import_router.dart';
import 'import_targets.dart';

/// Where the user wants incoming files to go.
enum ImportChoice { insert, create }

/// Carries out [ImportRouter]'s plans with the app's UI: asks "insert or
/// new?" when an editor is open, runs the PDF import flows, creates image
/// canvases, and explains files Len can't open.
///
/// [adopt] files a new notebook in the library (current folder etc.);
/// [show] opens new notebooks in editor tabs, the last one shown.
class ImportFlow {
  ImportFlow({required this.services, required this.adopt, required this.show});

  final AppServices services;
  final Notebook Function(Notebook notebook) adopt;
  final void Function(List<Notebook> notebooks) show;

  Future<void> _queue = Future.value();

  ImportTargets get _targets => services.incomingFiles.targets;

  /// Handles [files] once batches before it are done. [offerInsert]
  /// false (drops onto the library) always creates new notebooks.
  Future<void> enqueue(BuildContext context, List<XFile> files, {bool offerInsert = true}) =>
      _queue = _queue.then((_) async {
        if (!context.mounted) return;
        try {
          await run(context, files, offerInsert: offerInsert);
        } on Object catch (e, stack) {
          debugPrint('Opening incoming files failed: $e\n$stack');
          if (context.mounted) showMessage(context, 'Couldn’t open the files');
        }
      });

  /// Handles one batch of [files] now.
  Future<void> run(BuildContext context, List<XFile> files, {bool offerInsert = true}) async {
    final target = offerInsert ? _targets.active : null;
    ImportDestination? into;
    if (target != null && ImportRouter.shouldAsk(files, target.destination)) {
      final choice = await askWhere(context, files, target.destination);
      if (choice == null || !context.mounted) return;
      if (choice == ImportChoice.insert) into = target.destination;
    }
    final plan = ImportRouter.plan(files, into: into);
    final created = <Notebook>[];
    ({Notebook notebook, List<XFile> files})? canvas;
    for (final step in plan.steps) {
      if (!context.mounted) return;
      switch (step) {
        case InsertPdfPages(:final file):
          await target!.insertPdf(file);
        case InsertImages(:final files):
          await target!.insertImages(files);
        case NewPdfNotebook(:final file):
          final notebook = await importPdfFlow(context, file: file);
          if (notebook != null) created.add(adopt(notebook));
        case ImportLenFile(:final file):
          final result = await importLenFlow(context, file: file);
          // A notebook goes where the library is (and opens); folders and
          // backups show in the library.
          if (result != null && result.manifest.kind == LenArchiveKind.notebook) {
            final id = result.notebooks.firstOrNull;
            final notebook = id == null ? null : services.notebooks.get(id);
            if (notebook != null) created.add(adopt(notebook));
          }
        case NewImageCanvas(:final files, :final title):
          final notebook = adopt(_createCanvas(title));
          created.add(notebook);
          canvas = (notebook: notebook, files: files);
      }
    }
    final message = plan.unsupportedMessage;
    if (message != null && context.mounted) showMessage(context, message);
    if (created.isEmpty || !context.mounted) return;
    show(created);
    // Images need the canvas's editor (its viewport places them).
    if (canvas == null) return;
    final editor = await _targets.waitFor(canvas.notebook.id);
    await editor?.insertImages(canvas.files);
  }

  Notebook _createCanvas(String title) => services.notebooks.create(
    title: title,
    kind: NotebookKind.canvas,
    paper: PaperStyle.blank,
    coverColor: Palette.covers[5],
  );

  /// Asks whether [files] go into the open notebook [open] or new ones;
  /// null if cancelled.
  static Future<ImportChoice?> askWhere(
    BuildContext context,
    List<XFile> files,
    ImportDestination open,
  ) {
    final kinds = files.map(ImportRouter.kindOf).toSet();
    final onlyImages = !kinds.contains(IncomingKind.pdf);
    final name = files.length == 1 ? ImportRouter.nameOf(files.single) : null;
    final subject = name != null ? '“$name”' : '${files.length} files';
    final pdfsStayApart = kinds.contains(IncomingKind.pdf) && !open.acceptsPdf;
    final target = open.acceptsPdf ? 'notebook' : 'canvas';
    final message = [
      'Add $subject to “${open.title}”, or open '
          '${onlyImages ? 'a new canvas' : 'as a new notebook'}?',
      if (pdfsStayApart) 'PDFs always open as new notebooks: a canvas has no pages.',
    ].join('\n\n');
    return showDialog<ImportChoice>(
      context: context,
      builder: (context) => AppDialog(
        title: name != null ? 'Open “$name”' : 'Open ${files.length} files',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dialogFormWidth),
          child: Text(message),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportChoice.create),
            child: Text(onlyImages ? 'New canvas' : 'New notebook'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ImportChoice.insert),
            child: Text('Add to this $target'),
          ),
        ],
      ),
    );
  }
}
