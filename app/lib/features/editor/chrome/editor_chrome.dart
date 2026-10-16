import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/chrome_fade.dart';
import '../../../ui/messages.dart';
import '../editor_toolbar.dart';
import 'chrome_layout.dart';
import 'chrome_metrics.dart';
import 'editor_tips.dart';
import 'focus_handle.dart';
import 'gesture_hud.dart';
import 'peeking.dart';
import 'receding.dart';
import 'tip_banner.dart';
import 'toolbar_slot.dart';

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
    // The page sidebar's side: what floats over the page keeps to the rest.
    final aside = layout.aside;
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
                  top: layout.barBottom + layout.boxAbove,
                  bottom: safe.bottom + layout.boxBelow,
                  left: safe.left + aside.left,
                  right: safe.right + aside.right,
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
                visible: !focus && layout.hasBottomRow,
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
                left: aside.left,
                right: aside.right,
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
            left: aside.left,
            right: aside.right,
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
                left: Gaps.md + aside.left,
                right: Gaps.md + aside.right,
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
