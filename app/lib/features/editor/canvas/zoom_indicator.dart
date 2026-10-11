import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';

/// The zoom percentage, shown briefly whenever the zoom changes. Tapping
/// it (while shown) offers 50 %, 100 %, 200 % and "Fit content".
class ZoomIndicator extends StatefulWidget {
  const ZoomIndicator({
    super.key,
    required this.viewport,
    required this.onZoomTo,
    required this.onFit,
    this.quiet,
  });

  final ViewportController viewport;
  final ValueChanged<double> onZoomTo;
  final VoidCallback onFit;

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
  bool _visible = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.viewport.addListener(_onViewport);
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
    if (scale == _scale) return; // Panning only.
    if (widget.quiet?.call() ?? false) {
      _scale = scale;
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
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: Motion.medium,
        curve: Motion.standard,
        child: MenuAnchor(
          controller: _menu,
          onClose: _scheduleHide,
          menuChildren: [
            // A leading slot on every row keeps the labels aligned; the
            // current zoom is checked.
            for (final preset in ZoomIndicator.presets)
              MenuItemButton(
                leadingIcon: (_scale - preset).abs() < 0.005
                    ? const Icon(Icons.check_rounded)
                    : const SizedBox(width: 24),
                onPressed: () => widget.onZoomTo(preset),
                child: Text(_label(preset)),
              ),
            const Divider(),
            MenuItemButton(
              leadingIcon: const Icon(Icons.fit_screen_outlined),
              onPressed: widget.onFit,
              child: const Text('Fit content'),
            ),
          ],
          child: FloatingPanel(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.toolbar),
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
    );
  }
}
