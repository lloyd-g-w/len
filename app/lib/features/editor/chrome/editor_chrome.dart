import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../editor_toolbar.dart';
import '../toolbar/toolbar_metrics.dart';
import 'chrome_metrics.dart';
import 'editor_tips.dart';
import 'focus_handle.dart';
import 'gesture_hud.dart';
import 'peeking.dart';
import 'toolbar_slot.dart';

/// Where the chrome sits for a given pane, and how much of it the chrome
/// covers (so content can be kept clear of it).
@immutable
class ChromeLayout {
  const ChromeLayout({
    required this.dock,
    required this.barHeight,
    required this.safe,
    required this.hasNavigator,
    required this.width,
    required this.focus,
  });

  /// Where the toolbar is.
  final ToolbarDock dock;

  /// Height of the top bar (tab strip included) without the status bar.
  final double barHeight;

  /// System insets (status bar, gesture bar, notches).
  final EdgeInsets safe;
  final bool hasNavigator;
  final double width;
  final bool focus;

  /// Whether the editor is laid out for a phone.
  bool get phone => width < ChromeMetrics.compactWidth;

  /// Height of the tool row attached under the top bar (0 without one).
  double get toolRowHeight => dock == ToolbarDock.row ? ToolbarMetrics.rowHeight : 0;

  /// Height of the phone's bottom tool row, gesture inset excluded.
  double get bottomRowHeight => dock == ToolbarDock.bottom ? ToolbarMetrics.bottomHeight : 0;

  /// The indicator takes no permanent room on any display size.
  bool get navigatorPeeks => true;

  /// Bottom of the top chrome block (status bar, tabs, bar, tool row).
  double get barBottom => safe.top + barHeight + toolRowHeight;

  /// Where the page navigator's bottom edge sits.
  double get navigatorBottom => safe.bottom + bottomRowHeight + ChromeMetrics.edge;

  /// Screen space covered by chrome along the top and bottom edges. A
  /// floating palette covers no edge.
  EdgeInsets get covered {
    if (focus) return EdgeInsets.only(top: safe.top, bottom: safe.bottom);
    return EdgeInsets.only(top: barBottom, bottom: safe.bottom + bottomRowHeight);
  }

  /// [covered], plus the spot a peeking navigator appears in:
  /// floating controls along the bottom (the audio bar) stay clear of it.
  EdgeInsets get floatingInsets {
    final insets = covered;
    if (focus || !hasNavigator) return insets;
    return insets.copyWith(bottom: insets.bottom + ChromeMetrics.navigatorExtent);
  }
}

/// Lays the editor chrome over the canvas — the top bar (with the docked
/// tools inside or under it), the phone's bottom tool row or the floating
/// palette, the page navigator, the gesture HUD — and fades it away in
/// focus mode, leaving only a small [FocusHandle].
class EditorChrome extends StatelessWidget {
  const EditorChrome({
    super.key,
    required this.layout,
    required this.topBar,
    required this.toolbar,
    required this.hud,
    this.tips,
    this.notice,
    required this.onExitFocus,
    this.navigator,
    this.navigatorActivity,
    this.floatAt,
    this.onFloatMoved,
    this.puck,
    this.puckAt,
    this.onPuckMoved,
    this.dimmed = false,
  });

  /// The other pane of a split view is in use: the top bar and toolbar
  /// recede to 60 % ([Motion.fast]); a touch here brings them back.
  final bool dimmed;

  final ChromeLayout layout;

  /// The top bar; it carries the toolbar when docked inline or as a row.
  final Widget topBar;

  /// The toolbar for the bottom row or the floating palette (unused when
  /// the top bar carries it).
  final Widget toolbar;
  final Widget? navigator;

  /// Notifies when pages scroll or turn: shows a peeking navigator
  /// ([ChromeLayout.navigatorPeeks]).
  final Listenable? navigatorActivity;
  final HudController hud;

  /// One-time tips, shown under the HUD.
  final TipsController? tips;

  /// A standing notice under the tips (e.g. a PDF that can't be had).
  final Widget? notice;
  final VoidCallback onExitFocus;
  final (double, double)? floatAt;
  final ValueChanged<(double, double)>? onFloatMoved;

  /// Focus mode's tool puck (`ToolPuck`), where it was left ([puckAt],
  /// bottom centre by default).
  final Widget? puck;
  final (double, double)? puckAt;
  final ValueChanged<(double, double)>? onPuckMoved;

  @override
  Widget build(BuildContext context) {
    final focus = layout.focus;
    final safe = layout.safe;
    final scheme = Theme.of(context).colorScheme;
    Widget recede(Widget child) => AnimatedOpacity(
      opacity: dimmed ? 0.6 : 1,
      duration: Motion.fast,
      curve: Motion.standard,
      child: child,
    );
    return Stack(
      children: [
        if (layout.dock == ToolbarDock.floating)
          Positioned.fill(
            child: ToolbarSlot(
              toolbar: recede(toolbar),
              insets: EdgeInsets.only(
                top: layout.barBottom,
                bottom: safe.bottom,
                left: safe.left,
                right: safe.right,
              ),
              floatAt: floatAt,
              onFloatMoved: onFloatMoved,
              visible: !focus,
            ),
          ),
        if (layout.dock == ToolbarDock.bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChromeFade(
              visible: !focus,
              edge: const Offset(0, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Surfaces.chrome(scheme),
                  border: Border(top: Surfaces.chromeEdge(scheme)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: safe.bottom, left: safe.left, right: safe.right),
                  child: recede(toolbar),
                ),
              ),
            ),
          ),
        if (navigator case final navigator?)
          AnimatedPositioned(
            duration: Motion.slow,
            curve: Motion.emphasized,
            left: 0,
            right: 0,
            bottom: layout.navigatorBottom,
            child: Align(
              // Phones centre the indicator under the page; wider screens
              // tuck it into the bottom-right corner. Aligning (rather than
              // guessing a width) keeps it centred at any text scale.
              alignment: layout.phone ? Alignment.center : Alignment.centerRight,
              child: Padding(
                padding: layout.phone
                    ? EdgeInsets.only(left: safe.left, right: safe.right)
                    : EdgeInsets.only(right: safe.right + ChromeMetrics.edge),
                child: ChromeFade(
                  visible: !focus,
                  edge: const Offset(0, 1),
                  child: Peeking(
                    enabled: layout.navigatorPeeks,
                    activity: navigatorActivity,
                    child: navigator,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ChromeFade(visible: !focus, edge: const Offset(0, -1), child: recede(topBar)),
        ),
        Positioned(
          top: layout.covered.top + Gaps.xl,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureHud(controller: hud),
              if (tips case final tips?)
                Padding(
                  padding: const EdgeInsets.only(top: Gaps.sm, left: Gaps.md, right: Gaps.md),
                  child: TipBanner(controller: tips),
                ),
              if (notice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: Gaps.sm, left: Gaps.md, right: Gaps.md),
                  child: notice,
                ),
            ],
          ),
        ),
        // Only in focus mode: otherwise its controls would sit (hidden) in
        // the tree beside the toolbar's own.
        if (puck case final puck? when focus)
          Positioned.fill(
            child: ToolbarSlot(
              toolbar: puck,
              insets: safe,
              floatAt: puckAt ?? const (0.5, 1.0),
              onFloatMoved: onPuckMoved,
              visible: focus,
            ),
          ),
        Positioned(
          top: safe.top + Gaps.sm,
          right: safe.right + Gaps.sm,
          child: ChromeFade(
            visible: focus,
            edge: const Offset(0, -1),
            child: FocusHandle(onExit: onExitFocus),
          ),
        ),
      ],
    );
  }
}
