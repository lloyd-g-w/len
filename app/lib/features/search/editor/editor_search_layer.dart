import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Ctrl+F (Cmd+F) opens the search.
  static Map<ShortcutActivator, VoidCallback> shortcuts(EditorSearchController controller) => {
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): controller.open,
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): controller.open,
  };

  final EditorSearchController controller;

  /// Called after the bar closed (e.g. to give focus back to the canvas).
  final VoidCallback onClose;

  /// Screen space covered by the editor's top chrome; the bar goes below.
  final double top;

  /// Room the bar's field row takes, kept clear when revealing matches.
  static const double _barRow = 64;

  /// Widest the bar gets.
  static const double maxWidth = 440;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    controller.topInset = top + _barRow;
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
              top: top + 8,
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
