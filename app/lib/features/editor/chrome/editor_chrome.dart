import 'package:flutter/material.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_theme.dart';
import 'chrome_metrics.dart';
import 'focus_handle.dart';
import 'gesture_hud.dart';
import 'toolbar_slot.dart';

/// Where the chrome sits for a given screen, and how much of the screen it
/// covers (so content can be kept clear of it).
@immutable
class ChromeLayout {
  const ChromeLayout({
    required this.placement,
    required this.barHeight,
    required this.safe,
    required this.hasNavigator,
    required this.width,
    required this.focus,
    this.toolbarHeight,
  });

  /// Resolved toolbar placement (never `auto`).
  final ToolbarPlacement placement;

  /// Height of the top bar without the status bar.
  final double barHeight;

  /// System insets (status bar, gesture bar, notches).
  final EdgeInsets safe;
  final bool hasNavigator;
  final double width;
  final bool focus;

  /// Measured height of the toolbar panel; null until known.
  final double? toolbarHeight;

  /// Room the toolbar takes at the top or bottom edge.
  double get toolbarExtent => switch (toolbarHeight) {
    final h? => ChromeMetrics.toolbarExtentFor(h),
    null => ChromeMetrics.toolbarExtent,
  };

  /// The navigator sits above a bottom toolbar unless there is room beside it.
  bool get navigatorAboveToolbar => placement == ToolbarPlacement.bottom && width < 1180;

  /// Bottom of the top bar.
  double get barBottom => safe.top + barHeight;

  /// Screen space covered by chrome along the top and bottom edges.
  EdgeInsets get covered {
    if (focus) return EdgeInsets.only(top: safe.top, bottom: safe.bottom);
    final toolbarTop = placement == ToolbarPlacement.top ? toolbarExtent : 0.0;
    final toolbarBottom = placement == ToolbarPlacement.bottom ? toolbarExtent : 0.0;
    final navigator = hasNavigator ? ChromeMetrics.navigatorExtent : 0.0;
    final bottom = navigatorAboveToolbar
        ? toolbarBottom + navigator
        : (toolbarBottom > navigator ? toolbarBottom : navigator);
    return EdgeInsets.only(top: barBottom + toolbarTop, bottom: safe.bottom + bottom);
  }
}

/// Lays the editor chrome over the canvas — top bar, toolbar slot, page
/// navigator, gesture HUD — and animates it away in focus mode, leaving
/// only a small [FocusHandle].
class EditorChrome extends StatelessWidget {
  const EditorChrome({
    super.key,
    required this.layout,
    required this.topBar,
    required this.toolbar,
    required this.hud,
    required this.onExitFocus,
    this.navigator,
    this.floatAt,
    this.onFloatMoved,
    this.onToolbarHeight,
  });

  final ChromeLayout layout;
  final Widget topBar;
  final Widget toolbar;
  final Widget? navigator;
  final HudController hud;
  final VoidCallback onExitFocus;
  final (double, double)? floatAt;
  final ValueChanged<(double, double)>? onFloatMoved;
  final ValueChanged<double>? onToolbarHeight;

  @override
  Widget build(BuildContext context) {
    final focus = layout.focus;
    final safe = layout.safe;
    final navigatorBottom =
        safe.bottom +
        ChromeMetrics.edge +
        (layout.navigatorAboveToolbar ? layout.toolbarExtent : 0);
    return Stack(
      children: [
        Positioned.fill(
          child: ToolbarSlot(
            toolbar: toolbar,
            placement: layout.placement,
            insets: EdgeInsets.only(
              top: layout.barBottom,
              bottom: safe.bottom,
              left: safe.left,
              right: safe.right,
            ),
            floatAt: floatAt,
            onFloatMoved: onFloatMoved,
            onHeight: onToolbarHeight,
            visible: !focus,
          ),
        ),
        if (navigator case final navigator?)
          AnimatedPositioned(
            duration: Motion.slow,
            curve: Motion.emphasized,
            right: safe.right + ChromeMetrics.edge,
            bottom: navigatorBottom,
            child: _Hideable(visible: !focus, offset: const Offset(0, 0.4), child: navigator),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _Hideable(visible: !focus, offset: const Offset(0, -1), child: topBar),
        ),
        Positioned(
          top: layout.covered.top + Gaps.xl,
          left: 0,
          right: 0,
          child: Center(child: GestureHud(controller: hud)),
        ),
        Positioned(
          top: safe.top + Gaps.sm,
          right: safe.right + Gaps.sm,
          child: _Hideable(
            visible: focus,
            offset: const Offset(0, -0.5),
            child: FocusHandle(onExit: onExitFocus),
          ),
        ),
      ],
    );
  }
}

/// Slides and fades [child] away when not [visible] (and ignores input).
class _Hideable extends StatelessWidget {
  const _Hideable({required this.visible, required this.offset, required this.child});

  final bool visible;

  /// Where it slides to when hidden, in multiples of its size.
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : offset,
        duration: Motion.slow,
        curve: Motion.emphasized,
        child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: Motion.medium, child: child),
      ),
    );
  }
}
