import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_theme.dart';
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
    this.covered = const EdgeInsets.only(top: 72),
  });

  /// Ctrl+F (Cmd+F) opens the search.
  static Map<ShortcutActivator, VoidCallback> shortcuts(EditorSearchController controller) => {
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): controller.open,
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): controller.open,
  };

  final EditorSearchController controller;

  /// Called after the bar closed (e.g. to give focus back to the canvas).
  final VoidCallback onClose;

  /// Screen edges covered by the editor's chrome; the bar goes below the
  /// top, and revealed matches stay clear of both the chrome and the bar.
  final EdgeInsets covered;

  /// Room the bar's field row takes until the bar has been measured.
  static const double _barRow = 64;

  /// Widest the bar gets.
  static const double maxWidth = 440;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = covered.top;
    // Until the bar reports its height (with the result list, if shown).
    if (!controller.isOpen) controller.clear = covered.copyWith(top: top + Gaps.sm + _barRow);
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
              top: top + Gaps.sm,
              right: 12,
              left: narrow ? 12 : null,
              width: narrow ? null : maxWidth,
              child: _HeightReporter(
                onHeight: (h) => controller.clear = covered.copyWith(top: top + Gaps.sm + h),
                child: EditorSearchBar(controller: controller, onClose: onClose),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Reports its child's height after each layout (the search bar grows
/// with its result list), so revealed matches land below it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightReporter renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
