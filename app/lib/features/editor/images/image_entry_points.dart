import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../ui/app_theme.dart';
import '../../documents/import/import_router.dart';
import 'editor_images.dart';

/// Accepts files dragged onto the editor (desktop, web): images are
/// inserted where they are dropped, anything else (PDFs) is handed on as
/// if opened with Len; highlights the area while they hover.
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
        final images = <XFile>[], others = <XFile>[];
        for (final f in details.files) {
          (ImportRouter.kindOf(f) == IncomingKind.image ? images : others).add(f);
        }
        // PDFs (and Len files) go the way of Open with: with this notebook
        // open, asked whether to add them to it (UX_AUDIT R18-4).
        if (others.isNotEmpty) AppScope.read(context).incomingFiles.add(others);
        if (images.isEmpty) return;
        unawaited(widget.images.insertFiles(context, images, screen: details.localPosition));
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
