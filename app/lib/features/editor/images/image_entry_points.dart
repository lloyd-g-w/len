import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import '../chrome/canvas_guard.dart';
import 'editor_images.dart';
import 'image_import.dart';

/// The top bar's "Insert image" button: opens the file picker, or on
/// Android offers the camera too.
class InsertImageButton extends StatelessWidget {
  const InsertImageButton({super.key, required this.images});

  final EditorImages images;

  static const String tooltip = 'Insert image';

  @override
  Widget build(BuildContext context) {
    const icon = Symbols.add_photo_alternate_rounded;
    if (!EditorImages.canUseCamera) {
      return BarButton(
        tooltip: tooltip,
        icon: icon,
        onPressed: () => unawaited(images.pickFiles(context)),
      );
    }
    return ChromeMenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.photo_library_rounded),
          onPressed: () => unawaited(images.pickFiles(context)),
          child: const Text('Choose image…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.photo_camera_rounded),
          onPressed: () => unawaited(images.takePhoto(context)),
          child: const Text('Take photo'),
        ),
      ],
      builder: (context, menu, _) => BarButton(
        tooltip: tooltip,
        icon: icon,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// Accepts image files dragged onto the editor (desktop), inserting them
/// where they are dropped, and highlights the area while they hover.
///
/// Lies over the editor (filling it) without taking pointer events.
class ImageDropTarget extends StatefulWidget {
  const ImageDropTarget({super.key, required this.images});

  final EditorImages images;

  @override
  State<ImageDropTarget> createState() => _ImageDropTargetState();
}

class _ImageDropTargetState extends State<ImageDropTarget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // Dialogs and pushed screens must not receive drops meant for them.
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: current,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        final files = [
          for (final f in details.files)
            if (ImageImport.extensions.contains(f.name.split('.').last.toLowerCase())) f,
        ];
        if (files.isEmpty) return;
        unawaited(widget.images.insertFiles(context, files, screen: details.localPosition));
      },
      child: IgnorePointer(
        child: SizedBox.expand(
          child: _hovering
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.06),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
