import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import 'library_actions.dart';

/// The library search field's focus. [open] (Ctrl+F) also shows the field
/// where narrow headers keep it behind 🔍: a node that isn't in the tree
/// can't take focus.
class LibrarySearchFocus extends FocusNode {
  LibrarySearchFocus() : super(debugLabel: 'Library search');

  /// Shows the field and focuses it; set by the header.
  VoidCallback? onOpen;

  /// Focuses the field, showing it first if needed.
  void open() => context == null && onOpen != null ? onOpen!() : requestFocus();
}

/// The library's search field: typing filters the library; ✕ clears it
/// (or, with [onClose], closes the empty field).
class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.focus,
    required this.actions,
    this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final LibraryActions actions;

  /// Narrow layouts: ✕ closes the field (else it only clears it).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: Targets.menuRowHeight(context),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          focusNode: focus,
          onChanged: (q) => actions.controller.query = q,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: 'Search',
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(
              Symbols.search_rounded,
              color: scheme.onSurfaceVariant,
              size: Glyphs.bar,
            ),
            suffixIcon: controller.text.isEmpty && onClose == null
                ? null
                : IconButton(
                    tooltip: onClose == null || controller.text.isNotEmpty
                        ? 'Clear search'
                        : 'Close search',
                    iconSize: Glyphs.menu,
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      if (controller.text.isEmpty) {
                        onClose?.call();
                        return;
                      }
                      controller.clear();
                      actions.controller.query = '';
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
