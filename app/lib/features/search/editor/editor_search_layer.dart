import 'package:flutter/material.dart';

import '../highlighted_text.dart';
import 'editor_search_bar.dart';
import 'editor_search_controller.dart';
import 'search_highlight_painter.dart';

/// Everything the in-notebook search shows over the editor: highlights on
/// the surface and, while open, the search bar. Meant to fill the editor
/// (it lets pointer events through outside the bar).
class EditorSearchLayer extends StatelessWidget {
  const EditorSearchLayer({
    super.key,
    required this.controller,
    required this.onClose,
    this.top = 72,
  });

  final EditorSearchController controller;

  /// Called after the bar closed (e.g. to give focus back to the canvas).
  final VoidCallback onClose;

  /// Distance of the bar from the top (below the editor's top chrome).
  final double top;

  /// Widest the bar gets.
  static const double maxWidth = 440;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: SearchHighlightPainter(
                  controller: controller,
                  host: controller.host,
                  matchColor: SearchColors.match(scheme),
                  currentColor: SearchColors.current(scheme),
                ),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (!controller.isOpen) return const SizedBox.shrink();
            final width = MediaQuery.sizeOf(context).width;
            final narrow = width < maxWidth + 24;
            return Positioned(
              top: top + MediaQuery.paddingOf(context).top,
              right: 12,
              left: narrow ? 12 : null,
              width: narrow ? null : maxWidth,
              child: EditorSearchBar(controller: controller, onClose: onClose),
            );
          },
        ),
      ],
    );
  }
}

/// The editor's search button (opens the bar; Ctrl+F does too).
class EditorSearchButton extends StatelessWidget {
  const EditorSearchButton({super.key, required this.controller});

  final EditorSearchController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Search (Ctrl+F)',
    onPressed: controller.open,
    icon: const Icon(Icons.search_rounded),
  );
}
