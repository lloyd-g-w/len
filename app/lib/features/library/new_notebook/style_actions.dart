import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/notebook_style_repository.dart';
import '../../../domain/notebook_style.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/menus.dart';
import '../../../ui/text_prompt.dart';

/// Asks for a name and saves [choice] as a notebook style; null if
/// cancelled. [suggested] fills the name field.
Future<NotebookStyle?> saveNotebookStyle(
  BuildContext context,
  NotebookStyleRepository repo,
  NotebookChoice choice, {
  required String suggested,
}) async {
  final name = await showTextPrompt(
    context,
    title: 'Save as style',
    label: 'Name',
    initialValue: suggested,
    confirmLabel: 'Save',
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return repo.create(name: trimmed, choice: choice);
}

/// The menu of notebook style [style] at global position [at]: Default
/// (new notebooks start as it; checked when it is), Rename…, Delete….
/// Returns whether anything changed.
Future<bool> showNotebookStyleMenu(
  BuildContext context,
  NotebookStyleRepository repo,
  NotebookStyle style, {
  Offset? at,
}) async {
  final action = await showContextMenuAt<String>(
    context,
    at: at,
    items: [
      MenuRow(
        value: 'default',
        icon: Symbols.bookmark_sharp,
        label: 'Default for new notebooks',
        checked: style.isDefault,
      ),
      const MenuRow(value: 'rename', icon: Symbols.edit_sharp, label: 'Rename…'),
      const MenuRow(
        value: 'delete',
        icon: Symbols.delete_sharp,
        label: 'Delete…',
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return false;
  switch (action) {
    case 'default':
      repo.setDefault(style.id, isDefault: !style.isDefault);
      return true;
    case 'rename':
      final name = await showTextPrompt(
        context,
        title: 'Rename style',
        label: 'Name',
        initialValue: style.name,
        confirmLabel: 'Rename',
      );
      final trimmed = name?.trim() ?? '';
      if (trimmed.isEmpty || trimmed == style.name) return false;
      repo.rename(style.id, trimmed);
      return true;
    default:
      final confirmed = await confirmAction(
        context,
        title: 'Delete “${style.name}”?',
        message: 'Notebooks made with it keep their look',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (!confirmed) return false;
      repo.delete(style.id);
      return true;
  }
}
