import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'editor_images.dart';
import 'image_import.dart';

/// The toolbar's "Insert image" button: opens the file picker, or on
/// Android offers the camera too.
class InsertImageButton extends StatelessWidget {
  const InsertImageButton({super.key, required this.images});

  final EditorImages images;

  static const String tooltip = 'Insert image';

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.add_photo_alternate_outlined);
    if (!EditorImages.canUseCamera) {
      return IconButton(
        tooltip: tooltip,
        onPressed: () => unawaited(images.pickFiles(context)),
        icon: icon,
      );
    }
    return PopupMenuButton<bool>(
      tooltip: tooltip,
      icon: icon,
      onSelected: (camera) =>
          unawaited(camera ? images.takePhoto(context) : images.pickFiles(context)),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: false,
          child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Choose image')),
        ),
        PopupMenuItem(
          value: true,
          child: ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('Take photo')),
        ),
      ],
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
