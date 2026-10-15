import 'package:flutter/widgets.dart';

import '../editor_toolbar.dart';
import '../toolbar/toolbar_metrics.dart';
import 'chrome_metrics.dart';

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
    this.zoomBoxAtTop = false,
  });

  /// The same layout with the zoom window's box, [height] tall, docked
  /// above the bottom chrome (or, [atTop], under the top chrome).
  ChromeLayout withZoomBox(double height, {bool atTop = false}) => ChromeLayout(
    dock: dock,
    barHeight: barHeight,
    safe: safe,
    hasNavigator: hasNavigator,
    width: width,
    focus: focus,
    short: short,
    zoomBox: height,
    zoomBoxAtTop: atTop,
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

  /// Whether the zoom window's box docks under the top chrome.
  final bool zoomBoxAtTop;

  /// The box's height along the bottom edge (zero when it docks at the top).
  double get boxBelow => zoomBoxAtTop ? 0 : zoomBox;

  /// The box's height under the top chrome (zero when it docks at the bottom).
  double get boxAbove => zoomBoxAtTop ? zoomBox : 0;

  /// Where the zoom window's box sits: on the bottom tool row (in focus
  /// mode, on the screen's safe edge).
  double get zoomBoxBottom => safe.bottom + (focus ? 0 : bottomRowHeight);

  /// Where the box's top lies when it docks at the top: under the top
  /// chrome (in focus mode, the screen's safe edge).
  double get zoomBoxTop => focus ? safe.top : barBottom;

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
  double get navigatorBottom => safe.bottom + bottomRowHeight + boxBelow + ChromeMetrics.edge;

  /// Screen space covered by chrome along the top and bottom edges. A
  /// floating palette covers no edge.
  EdgeInsets get covered {
    if (focus) return EdgeInsets.only(top: safe.top + boxAbove, bottom: safe.bottom + boxBelow);
    return EdgeInsets.only(
      top: barBottom + boxAbove,
      bottom: safe.bottom + bottomRowHeight + boxBelow,
    );
  }

  /// [covered], plus the spot a peeking navigator appears in: floating
  /// slips along the bottom (tips) stay clear of it.
  EdgeInsets get floatingInsets {
    final insets = covered;
    if (focus || !hasNavigator) return insets;
    return insets.copyWith(bottom: insets.bottom + ChromeMetrics.navigatorExtent);
  }
}
