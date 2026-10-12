import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/text_prompt.dart';
import '../documents/template_picker.dart';
import 'shared/shared_notebook.dart';

/// Asks for a new name for [shared]'s notebook and renames it (in every
/// editor of it, and its tab).
Future<void> renameNotebook(BuildContext context, SharedNotebook shared) async {
  final title = await showTextPrompt(
    context,
    title: 'Rename notebook',
    label: 'Name',
    initialValue: shared.notebook.title,
    confirmLabel: 'Rename',
  );
  if (title == null || title.isEmpty || !context.mounted) return;
  shared.update((n) => n.copyWith(title: title));
}

/// Changes the template and paper colour of [shared]'s canvas.
Future<void> pickCanvasBackground(BuildContext context, SharedNotebook shared) async {
  final notebook = shared.notebook;
  final choice = await showTemplatePicker(
    context,
    initial: PageTemplate(paper: notebook.paper, color: notebook.paperColor),
    mode: TemplatePickerMode.canvas,
  );
  if (choice == null || !context.mounted) return;
  final template = choice.template;
  shared.update((n) => n.copyWith(paper: template.paper, paperColor: template.color));
}

/// The folder [notebook] is filed in, shown under its title.
String? folderNameOf(AppServices services, Notebook notebook) {
  final id = notebook.folderId;
  return id == null ? null : services.folders.get(id)?.name;
}
