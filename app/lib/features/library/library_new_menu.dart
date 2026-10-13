import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../settings/keyboard_shortcuts.dart' show modifierLabel;
import 'library_actions.dart';
import 'library_menus.dart';

/// What ⊕▾ (and a long press on the phone's ⊕) creates.
enum NewChoice { notebook, canvas, pdf, folder }

/// The rows of ⊕▾: New notebook, New canvas, Import PDF…, New folder.
List<PopupMenuEntry<NewChoice>> newMenuItems() => [
  MenuRow(
    value: NewChoice.notebook,
    icon: Symbols.menu_book_sharp,
    label: 'New notebook',
    shortcut: '${modifierLabel()}+N',
  ),
  const MenuRow(value: NewChoice.canvas, icon: Symbols.all_inclusive_sharp, label: 'New canvas'),
  const MenuRow(value: NewChoice.pdf, icon: Symbols.picture_as_pdf_sharp, label: 'Import PDF…'),
  const PopupMenuDivider(),
  MenuRow(
    value: NewChoice.folder,
    icon: Symbols.create_new_folder_sharp,
    label: 'New folder…',
    shortcut: '${modifierLabel()}+Shift+N',
  ),
];

/// Creates what [choice] says.
Future<void> runNewChoice(BuildContext context, LibraryActions actions, NewChoice choice) =>
    switch (choice) {
      NewChoice.notebook => actions.createNotebook(context),
      NewChoice.canvas => actions.createNotebook(context, kind: NotebookKind.canvas),
      NewChoice.pdf => actions.importPdf(context),
      NewChoice.folder => actions.createFolder(context),
    };

/// ⊕▾ (wide screens).
class LibraryNewMenu extends StatelessWidget {
  const LibraryNewMenu({super.key, required this.actions});

  final LibraryActions actions;

  @override
  Widget build(BuildContext context) {
    return MenuIconButton<NewChoice>(
      tooltip: 'New',
      icon: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.add_circle_sharp),
          Icon(Symbols.arrow_drop_down_sharp, size: Glyphs.menu),
        ],
      ),
      items: newMenuItems,
      onSelected: (choice) => unawaited(runNewChoice(context, actions, choice)),
    );
  }
}
