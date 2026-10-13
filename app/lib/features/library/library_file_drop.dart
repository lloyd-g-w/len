import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// Accepts PDFs and images dragged onto the library (desktop, web, and
/// Android split screen) and hands them to [onFiles]; highlights the
/// library while files hover over it.
class LibraryFileDrop extends StatefulWidget {
  const LibraryFileDrop({super.key, required this.onFiles, required this.child});

  final void Function(List<XFile> files) onFiles;
  final Widget child;

  @override
  State<LibraryFileDrop> createState() => _LibraryFileDropState();
}

class _LibraryFileDropState extends State<LibraryFileDrop> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    // Screens pushed over the library (the editor) take their own drops.
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
            if (f is! DropItemDirectory) f,
        ];
        if (files.isNotEmpty) widget.onFiles(files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.06),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Center(
                    child: OverlaySurface(
                      child: Padding(
                        padding: const EdgeInsets.all(Gaps.lg),
                        child: Text(
                          'Drop PDFs or images to open them',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
