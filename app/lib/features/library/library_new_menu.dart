import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import '../settings/keyboard_shortcuts.dart' show modifierLabel;
import 'library_actions.dart';
import 'library_menus.dart';

/// What ⊕▾ (and a long press on the phone's ⊕) creates.
enum NewChoice { notebook, pdf, len, folder }

/// The rows of ⊕▾: New notebook, Import PDF…, Import Len file…, New
/// folder… (a canvas is a choice in the new-notebook sheet).
List<PopupMenuEntry<NewChoice>> newMenuItems() => [
  MenuRow(
    value: NewChoice.notebook,
    icon: Symbols.menu_book_sharp,
    label: 'New notebook',
    shortcut: '${modifierLabel()}+N',
  ),
  const MenuRow(value: NewChoice.pdf, icon: Symbols.picture_as_pdf_sharp, label: 'Import PDF…'),
  const MenuRow(value: NewChoice.len, icon: Symbols.file_open_sharp, label: 'Import Len file…'),
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
      NewChoice.pdf => actions.importPdf(context),
      NewChoice.len => actions.importLen(context),
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
