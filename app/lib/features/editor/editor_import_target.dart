import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

import '../documents/import/import_router.dart';
import '../documents/import/import_targets.dart';
import 'editor_session.dart';

/// Lets files opened with / shared to Len go into the shown editor: PDF
/// pages after the current page (paged notebooks), images on the current
/// page or the canvas.
class EditorImportTarget implements ImportTarget {
  EditorImportTarget({
    required this.context,
    required this.session,
    required this.notebookId,
    required this.title,
  });

  /// The editor screen's context (dialogs, messages).
  final BuildContext context;
  final EditorSession session;

  @override
  final String notebookId;

  /// The notebook's current title.
  final String Function() title;

  @override
  ImportDestination get destination =>
      ImportDestination(title: title(), acceptsPdf: session.commands != null);

  @override
  Future<void> insertPdf(XFile file) async {
    final commands = session.commands;
    if (commands == null || !context.mounted) return;
    await commands.insertPdf(context, file: file);
  }

  @override
  Future<void> insertImages(List<XFile> files) async {
    // A just-opened editor has no viewport size until it is laid out.
    for (var i = 0; i < 10 && session.viewport.size.isEmpty; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!context.mounted) return;
    await session.images.insertFiles(context, files);
  }
}
