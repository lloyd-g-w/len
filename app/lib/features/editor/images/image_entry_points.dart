import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'editor_images.dart';
import 'image_import.dart';

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
