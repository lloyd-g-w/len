import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../chrome/canvas_guard.dart';
import '../tools/tool_icons.dart';

/// What Insert ⊕ offers: an image, a photo (Android), and in paged
/// notebooks scanned pages and pages from a PDF. Null entries are left out. (A page with a
/// template: hold "Add page after" in the page menu, UX_AUDIT R9-3.)
@immutable
class InsertActions {
  const InsertActions({required this.image, this.photo, this.scan, this.pdfPages});

  final VoidCallback image;
  final VoidCallback? photo;
  final VoidCallback? scan;
  final VoidCallback? pdfPages;

  List<(IconData, String, VoidCallback)> get _entries => [
    (Symbols.image_sharp, 'Image…', image),
    if (photo case final photo?) (Symbols.photo_camera_sharp, 'Take photo', photo),
    if (scan case final scan?) (Symbols.document_scanner_sharp, 'Scan document…', scan),
    if (pdfPages case final pdf?) (Symbols.picture_as_pdf_sharp, 'Pages from PDF…', pdf),
  ];

  /// The entries as menu items of a [ChromeMenuAnchor].
  List<Widget> menuItems() => [
    for (final (icon, label, onPressed) in _entries)
      MenuItemButton(leadingIcon: Icon(icon), onPressed: onPressed, child: Text(label)),
  ];

  /// Shows the entries as a menu at [context]'s widget and runs the one
  /// picked (the phone tool switcher's Insert tile).
  Future<void> showAt(BuildContext context) async {
    final entries = _entries;
    final picked = await showContextMenuAt<int>(
      context,
      items: [
        for (final (i, (icon, label, _)) in entries.indexed)
          MenuRow(value: i, icon: icon, label: label),
      ],
    );
    if (picked != null) entries[picked].$3();
  }
}

/// Insert ⊕: a button beside the tools (not a tool) opening the insert
/// menu.
class InsertButton extends StatelessWidget {
  const InsertButton({super.key, required this.actions, this.size});

  final InsertActions actions;

  /// The button's cell (the tool cells' size).
  final double? size;

  static const String tooltip = 'Insert';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChromeMenuAnchor(
      menuChildren: actions.menuItems(),
      builder: (context, menu, _) => SizedBox.square(
        dimension: size,
        child: Center(
          child: IconButton(
            tooltip: tooltip,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            iconSize: Glyphs.bar,
            constraints: const BoxConstraints.tightFor(width: Targets.bar, height: Targets.bar),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              // A 48-dp hit area on touch around the 40-dp visual.
              tapTargetSize: Targets.touchFirst
                  ? MaterialTapTargetSize.padded
                  : MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
            ),
            icon: const ToolIcon(ToolIconKind.insert),
          ),
        ),
      ),
    );
  }
}
