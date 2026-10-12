import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/measure_size.dart';
import 'chrome_metrics.dart';

/// Where the toolbar actually sits on screen.
enum ToolbarPosition { top, bottom, floating }

/// Resolves a [ToolbarPlacement] for a screen [width]: docked at the top on
/// wide screens (from [ChromeMetrics.topToolbarWidth]) if the toolbar,
/// [toolbarWidth] wide on one row, fits there; otherwise at the bottom,
/// within thumb reach.
ToolbarPosition resolvePlacement(
  ToolbarPlacement placement,
  double width, {
  required double toolbarWidth,
}) {
  if (placement == ToolbarPlacement.floating) return ToolbarPosition.floating;
  final fits =
      width >= ChromeMetrics.topToolbarWidth && toolbarWidth + 2 * ChromeMetrics.edge <= width;
  return fits ? ToolbarPosition.top : ToolbarPosition.bottom;
}

/// Hosts the pen toolbar: centred under the top bar, docked at the bottom,
/// or floating where the user dragged it (by its grip). Moving between
/// placements animates. Fills the editor; only the toolbar takes input.
class ToolbarSlot extends StatefulWidget {
  const ToolbarSlot({
    super.key,
    required this.toolbar,
    required this.placement,
    required this.insets,
    this.floatAt,
    this.onFloatMoved,
    this.onHeight,
    this.visible = true,
  });

  final Widget toolbar;

  /// Where the toolbar sits.
  final ToolbarPosition placement;

  /// Space taken by other chrome (top bar, safe areas) that the toolbar
  /// must stay clear of.
  final EdgeInsets insets;

  /// Floating position as fractions (0..1) of the free area.
  final (double, double)? floatAt;

  /// Called when a drag of the floating toolbar ends.
  final ValueChanged<(double, double)>? onFloatMoved;

  /// Reports the toolbar's height whenever it changes (it wraps to two
  /// rows when narrow), so content can keep clear of it.
  final ValueChanged<double>? onHeight;

  /// False in focus mode: the toolbar fades out and ignores input.
  final bool visible;

  @override
  State<ToolbarSlot> createState() => _ToolbarSlotState();
}

class _ToolbarSlotState extends State<ToolbarSlot> {
  /// Position while dragging, as an [Alignment] within the free area.
  Alignment? _dragging;
  final GlobalKey _panel = GlobalKey();

  Alignment get _alignment {
    final dragging = _dragging;
    if (dragging != null) return dragging;
    return switch (widget.placement) {
      ToolbarPosition.bottom => Alignment.bottomCenter,
      ToolbarPosition.floating => _floatAlignment,
      ToolbarPosition.top => Alignment.topCenter,
    };
  }

  Alignment get _floatAlignment {
    final (x, y) = widget.floatAt ?? (0.5, 0.82);
    return Alignment(x * 2 - 1, y * 2 - 1);
  }

  void _drag(DragUpdateDetails d, Size area) {
    final child = _panel.currentContext?.size ?? Size.zero;
    final free = Size(
      (area.width - child.width).clamp(1, double.infinity),
      (area.height - child.height).clamp(1, double.infinity),
    );
    final current = _dragging ?? _floatAlignment;
    setState(() {
      _dragging = Alignment(
        (current.x + d.delta.dx * 2 / free.width).clamp(-1, 1),
        (current.y + d.delta.dy * 2 / free.height).clamp(-1, 1),
      );
    });
  }

  void _endDrag() {
    final a = _dragging;
    if (a == null) return;
    widget.onFloatMoved?.call(((a.x + 1) / 2, (a.y + 1) / 2));
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final floating = widget.placement == ToolbarPosition.floating;
    final padding = widget.insets + const EdgeInsets.all(ChromeMetrics.edge);
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedAlign(
          alignment: _alignment,
          duration: _dragging != null ? Duration.zero : Motion.slow,
          curve: Motion.emphasized,
          child: ChromeFade(
            visible: widget.visible,
            edge: switch (widget.placement) {
              ToolbarPosition.top => const Offset(0, -1),
              ToolbarPosition.bottom || ToolbarPosition.floating => const Offset(0, 1),
            },
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: MeasureSize(
                onChange: (size) => widget.onHeight?.call(size.height),
                child: ConstrainedBox(
                  key: _panel,
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (floating) ...[
                        _Grip(onDrag: (d) => _drag(d, constraints.biggest), onEnd: _endDrag),
                        const SizedBox(width: Gaps.xs),
                      ],
                      Flexible(child: widget.toolbar),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle by which the floating toolbar is dragged.
class _Grip extends StatelessWidget {
  const _Grip({required this.onDrag, required this.onEnd});

  final GestureDragUpdateCallback onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Drag to move the toolbar',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: onDrag,
          onPanEnd: (_) => onEnd(),
          onPanCancel: onEnd,
          child: FloatingPanel(
            radius: Radii.pill,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 28,
              height: 48,
              child: Icon(Symbols.drag_indicator_rounded, size: 20, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
