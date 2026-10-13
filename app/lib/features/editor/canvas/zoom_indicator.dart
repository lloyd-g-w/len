import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/menus.dart';
import '../chrome/chrome_metrics.dart';

/// The zoom percentage, peeking like the page indicator (REDESIGN §2.4):
/// shown when the canvas opens and while the view moves (zoom or pan), for
/// [linger] after. Tapping it (while shown) offers 50 %, 100 %, 200 %,
/// "Fit content" and "Back to start": the one home of the canvas's
/// navigation commands.
class ZoomIndicator extends StatefulWidget {
  const ZoomIndicator({
    super.key,
    required this.viewport,
    required this.onZoomTo,
    required this.onFit,
    required this.onBackToStart,
    this.quiet,
  });

  final ViewportController viewport;
  final ValueChanged<double> onZoomTo;
  final VoidCallback onFit;
  final VoidCallback onBackToStart;

  /// While this returns true, zoom changes are not announced (e.g. the
  /// view a canvas opens with).
  final bool Function()? quiet;

  /// How long the indicator stays after the zoom stops changing.
  static const Duration linger = Duration(milliseconds: 1500);

  /// Zoom levels offered in the menu.
  static const List<double> presets = [0.5, 1, 2];

  @override
  State<ZoomIndicator> createState() => _ZoomIndicatorState();
}

class _ZoomIndicatorState extends State<ZoomIndicator> {
  final MenuController _menu = MenuController();
  late double _scale = widget.viewport.scale;
  late Offset _offset = widget.viewport.offset;

  /// Shown when the canvas opens, so its menu is found.
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.viewport.addListener(_onViewport);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(ZoomIndicator old) {
    super.didUpdateWidget(old);
    if (old.viewport != widget.viewport) {
      old.viewport.removeListener(_onViewport);
      widget.viewport.addListener(_onViewport);
    }
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_onViewport);
    _hide?.cancel();
    super.dispose();
  }

  void _onViewport() {
    final scale = widget.viewport.scale;
    final offset = widget.viewport.offset;
    if (scale == _scale && offset == _offset) return;
    final quiet = widget.quiet?.call() ?? false;
    _offset = offset;
    if (quiet) {
      // The view the canvas opens with: just follow it.
      if (scale != _scale) setState(() => _scale = scale);
      return;
    }
    setState(() {
      _scale = scale;
      _visible = true;
    });
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(ZoomIndicator.linger, () {
      if (!mounted) return;
      if (_menu.isOpen) return _scheduleHide();
      setState(() => _visible = false);
    });
  }

  static String _label(double scale) => '${(scale * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Shortcut hints only where a keyboard is likely (as in the ⋯ menu).
    final keys = MediaQuery.sizeOf(context).width >= ChromeMetrics.compactWidth;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: Motion.medium,
        curve: Motion.standard,
        child: MenuEdgeMargin(
          child: MenuAnchor(
            controller: _menu,
            reservedPadding: menuReservedPadding(context),
            onClose: _scheduleHide,
            menuChildren: [
              // A leading slot on every row keeps the labels aligned; the
              // current zoom is checked.
              for (final preset in ZoomIndicator.presets)
                MenuItemButton(
                  leadingIcon: (_scale - preset).abs() < 0.005
                      ? const Icon(Symbols.check_rounded)
                      : const SizedBox(width: 24),
                  onPressed: () => widget.onZoomTo(preset),
                  child: Text(_label(preset)),
                ),
              const Divider(),
              MenuItemButton(
                leadingIcon: const Icon(Symbols.fit_screen_rounded),
                onPressed: widget.onFit,
                shortcut: keys
                    ? const SingleActivator(LogicalKeyboardKey.digit1, shift: true)
                    : null,
                child: const Text('Fit content'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Symbols.home_rounded),
                onPressed: widget.onBackToStart,
                shortcut: keys ? const SingleActivator(LogicalKeyboardKey.home) : null,
                child: const Text('Back to start'),
              ),
            ],
            child: FloatingPanel(
              radius: Radii.pill,
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.pill),
                onTap: () => _menu.isOpen ? _menu.close() : _menu.open(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm),
                  child: Text(
                    _label(_scale),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
