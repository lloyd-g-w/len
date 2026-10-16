import 'package:flutter/widgets.dart';

import '../../domain/preferences.dart';
import 'chrome/chrome_layout.dart';
import 'chrome/chrome_metrics.dart';
import 'chrome/editor_top_bar.dart';
import 'editor_session.dart';
import 'editor_toolbar.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar/toolbar_metrics.dart';
import 'zoom/zoom_box.dart';

/// Decides where the toolbar goes in a pane of a given width — inside the
/// top bar when the bar fits it on one row (measured from the tools and
/// slot counts), else as a row under the bar, at the bottom on phones, or
/// floating — and notifies when that may change (slots added or removed).
/// Switching tools never notifies: the reserved strip is the widest any
/// tool needs.
class ToolbarMeasure extends ChangeNotifier {
  ToolbarMeasure(this.session) {
    _strip = ToolbarMetrics.strip(session.tools);
    session.tools.addListener(_onTools);
    session.zoomWindow.opened.addListener(notifyListeners);
    session.zoomWindow.boxHeight.addListener(notifyListeners);
  }

  final EditorSession session;
  late double _strip;

  void _onTools() {
    final strip = ToolbarMetrics.strip(session.tools);
    if (strip == _strip) return;
    _strip = strip;
    notifyListeners();
  }

  /// Where the toolbar sits in a pane of [size]: short windows (a phone
  /// held sideways) keep the chrome to one row, with the phone's switcher
  /// inside the bar when the full tools don't fit there.
  ToolbarDock dockFor(Size size) {
    if (session.services.preferences.toolbarPlacement == ToolbarPlacement.floating) {
      return ToolbarDock.floating;
    }
    if (size.width < ChromeMetrics.compactWidth) return ToolbarDock.bottom;
    final paged = session.doc != null;
    if (ToolbarMetrics.fitsOneRow(size.width, session.tools, paged: paged)) {
      return ToolbarDock.inline;
    }
    return ChromeMetrics.short(size.height) ? ToolbarDock.slim : ToolbarDock.row;
  }

  /// How the chrome lays out in an editor pane of [size], with [tabs] (or
  /// an empty [band] in their place) in the top bar, both panes of a
  /// [split] view shown; [focus] hides it.
  ChromeLayout layout({
    required Size size,
    required EdgeInsets safe,
    required OpenNotebooks? tabs,
    required bool focus,
    bool band = false,
    bool split = false,
    bool keyboard = false,
    EdgeInsets aside = EdgeInsets.zero,
  }) {
    final dock = dockFor(size);
    final layout = ChromeLayout(
      dock: dock,
      barHeight: EditorTopBar.heightFor(size, tabs, dock: dock, band: band, split: split),
      safe: safe,
      hasNavigator: session.doc != null,
      width: size.width,
      focus: focus,
      short: ChromeMetrics.short(size.height),
      keyboard: keyboard,
      aside: aside,
    );
    if (!session.zoomWindow.isOpen) return layout;
    final zoom = session.zoomWindow;
    final free = size.height - layout.covered.vertical;
    return layout.withZoomBox(
      ZoomBox.heightFor(free, chosen: zoom.boxHeight.value),
      atTop: session.services.preferences.zoomBoxAtTop,
    );
  }

  @override
  void dispose() {
    session.tools.removeListener(_onTools);
    session.zoomWindow.opened.removeListener(notifyListeners);
    session.zoomWindow.boxHeight.removeListener(notifyListeners);
    super.dispose();
  }
}
