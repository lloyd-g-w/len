import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/messages.dart';
import '../editor_toolbar.dart';
import '../toolbar/toolbar_metrics.dart';
import 'chrome_metrics.dart';
import 'editor_tips.dart';
import 'focus_handle.dart';
import 'gesture_hud.dart';
import 'peeking.dart';
import 'receding.dart';
import 'tip_banner.dart';
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
    this.short = false,
    this.zoomBox = 0,
  });

  /// The same layout with the zoom window's box, [height] tall, docked
  /// above the bottom chrome.
  ChromeLayout withZoomBox(double height) => ChromeLayout(
    dock: dock,
    barHeight: barHeight,
    safe: safe,
    hasNavigator: hasNavigator,
    width: width,
    focus: focus,
    short: short,
    zoomBox: height,
  );

  /// Where the toolbar is.
  final ToolbarDock dock;

  /// Height of the top bar (tab strip included) without the status bar.
  final double barHeight;

  /// System insets (status bar, gesture bar, notches).
  final EdgeInsets safe;
  final bool hasNavigator;
  final double width;
  final bool focus;

  /// A short window (a phone held sideways): the chrome is one row.
  final bool short;

  /// Height of the zoom window's box (0 when it is closed).
  final double zoomBox;

  /// Where the zoom window's box sits: on the bottom tool row (in focus
  /// mode, on the screen's safe edge).
  double get zoomBoxBottom => safe.bottom + (focus ? 0 : bottomRowHeight);

  /// Whether the editor is laid out for a phone.
  bool get phone => width < ChromeMetrics.compactWidth;

  /// Whether the top bar is the phone's compact one (back, undo, redo, ⋯;
  /// audio and the open notebooks in ⋯): phones and short windows.
  bool get compactBar => phone || dock == ToolbarDock.slim;

  /// Height of the tool row attached under the top bar (0 without one).
  double get toolRowHeight => dock == ToolbarDock.row ? ToolbarMetrics.rowHeight : 0;

  /// Height of the phone's bottom tool row, gesture inset excluded.
  double get bottomRowHeight => dock == ToolbarDock.bottom ? ToolbarMetrics.bottomHeight : 0;

  /// The indicator takes no permanent room on any display size.
  bool get navigatorPeeks => true;

  /// Bottom of the top chrome block (status bar, tabs, bar, tool row).
  double get barBottom => safe.top + barHeight + toolRowHeight;

  /// Where the page navigator's bottom edge sits.
  double get navigatorBottom => safe.bottom + bottomRowHeight + zoomBox + ChromeMetrics.edge;

  /// Screen space covered by chrome along the top and bottom edges. A
  /// floating palette covers no edge.
  EdgeInsets get covered {
    if (focus) return EdgeInsets.only(top: safe.top, bottom: safe.bottom + zoomBox);
    return EdgeInsets.only(top: barBottom, bottom: safe.bottom + bottomRowHeight + zoomBox);
  }

  /// [covered], plus the spot a peeking navigator appears in: floating
  /// slips along the bottom (tips) stay clear of it.
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
    this.puckBlocked,
    this.dimmed = false,
    this.presenting = false,
    this.bottomStrip,
  });

  /// Height of a strip docked along the bottom of the canvas (the audio
  /// strip): the page indicator and tips sit above it.
  final ValueListenable<double>? bottomStrip;

  /// In focus mode, hides the puck and the exit button too (a two-finger
  /// long press toggles it; F11 / Esc still leave focus mode).
  final bool presenting;

  /// The other pane of a split view is in use: what is on the top bar and
  /// toolbar recedes ([Receding]; the bars keep their surfaces); a touch
  /// here brings it back.
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

  /// Whether ink lies under a rectangle of the editor: the puck released
  /// over it moves clear (`ToolbarSlot.blocked`).
  final bool Function(Rect rect)? puckBlocked;

  /// [child] positioned [bottomStrip]'s height higher.
  Widget _lifted(Widget Function(double strip) child) => bottomStrip == null
      ? child(0)
      : ValueListenableBuilder(
          valueListenable: bottomStrip!,
          builder: (context, strip, _) => child(strip),
        );

  @override
  Widget build(BuildContext context) {
    final focus = layout.focus;
    final safe = layout.safe;
    final scheme = Theme.of(context).colorScheme;
    return RecedeScope(
      dimmed: dimmed,
      child: Stack(
        children: [
          if (layout.dock == ToolbarDock.floating)
            Positioned.fill(
              child: ToolbarSlot(
                toolbar: toolbar,
                insets: EdgeInsets.only(
                  top: layout.barBottom,
                  bottom: safe.bottom + layout.zoomBox,
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
                    padding: EdgeInsets.only(
                      bottom: safe.bottom,
                      left: safe.left,
                      right: safe.right,
                    ),
                    child: Receding(child: toolbar),
                  ),
                ),
              ),
            ),
          if (navigator case final navigator?)
            _lifted(
              (strip) => AnimatedPositioned(
                duration: Motion.slow,
                curve: Motion.emphasized,
                left: 0,
                right: 0,
                bottom: layout.navigatorBottom + strip,
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
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ChromeFade(visible: !focus, edge: const Offset(0, -1), child: topBar),
          ),
          Positioned(
            top: layout.covered.top + Gaps.xl,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureHud(controller: hud),
                if (notice case final notice?)
                  Padding(
                    padding: const EdgeInsets.only(top: Gaps.sm, left: Gaps.md, right: Gaps.md),
                    // One message at a time: it waits while a snack bar shows.
                    child: MessageQueue.stepAside(child: notice),
                  ),
              ],
            ),
          ),
          // Tips sit at the bottom, where messages go (not over the first
          // lines of writing), and step aside while a snack bar shows.
          if (tips case final tips?)
            _lifted(
              (strip) => Positioned(
                bottom: layout.floatingInsets.bottom + strip + Gaps.lg,
                left: Gaps.md,
                right: Gaps.md,
                child: Center(
                  child: MessageQueue.stepAside(child: TipBanner(controller: tips)),
                ),
              ),
            ),
          // Only in focus mode: otherwise its controls would sit (hidden) in
          // the tree beside the toolbar's own.
          if (puck case final puck? when focus && !presenting)
            Positioned.fill(
              child: ToolbarSlot(
                toolbar: puck,
                insets: safe,
                floatAt: puckAt ?? const (0.5, 1.0),
                onFloatMoved: onPuckMoved,
                blocked: puckBlocked,
                visible: focus,
              ),
            ),
          Positioned(
            top: safe.top + Gaps.sm,
            right: safe.right + Gaps.sm,
            child: ChromeFade(
              visible: focus && !presenting,
              edge: const Offset(0, -1),
              child: FocusHandle(onExit: onExitFocus, active: focus && !presenting),
            ),
          ),
        ],
      ),
    );
  }
}
