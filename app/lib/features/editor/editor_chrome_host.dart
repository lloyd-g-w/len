import 'package:flutter/material.dart';

import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../audio/notebook_audio.dart';
import '../audio/ui/audio_bar_button.dart';
import 'chrome/chrome_metrics.dart';
import 'chrome/editor_chrome.dart';
import 'chrome/editor_tips.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/gesture_hud.dart';
import 'chrome/missing_pdf_notice.dart';
import 'chrome/tool_puck.dart';
import 'document/document_layout.dart';
import 'editor_actions.dart';
import 'editor_session.dart';
import 'editor_toolbar.dart';
import 'images/editor_images.dart';
import 'pen/ink_paper.dart';
import 'split/parked_pane_notice.dart';
import 'split/split_controller.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar/insert_menu.dart';
import 'toolbar/toolbar_metrics.dart';

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
  }

  final EditorSession session;
  late double _strip;

  void _onTools() {
    final strip = ToolbarMetrics.strip(session.tools);
    if (strip == _strip) return;
    _strip = strip;
    notifyListeners();
  }

  /// Where the toolbar sits in a pane [width] wide.
  ToolbarDock dockFor(double width) {
    if (session.services.preferences.toolbarPlacement == ToolbarPlacement.floating) {
      return ToolbarDock.floating;
    }
    if (width < ChromeMetrics.compactWidth) return ToolbarDock.bottom;
    final paged = session.doc != null;
    return ToolbarMetrics.fitsOneRow(width, session.tools, paged: paged)
        ? ToolbarDock.inline
        : ToolbarDock.row;
  }

  /// How the chrome lays out in an editor [width] wide, with [tabs] (or
  /// an empty [band] in their place) in the top bar; [focus] hides it.
  ChromeLayout layout({
    required double width,
    required EdgeInsets safe,
    required OpenNotebooks? tabs,
    required bool focus,
    bool band = false,
  }) => ChromeLayout(
    dock: dockFor(width),
    barHeight: EditorTopBar.heightFor(width, tabs, band: band),
    safe: safe,
    hasNavigator: session.doc != null,
    width: width,
    focus: focus,
  );

  @override
  void dispose() {
    session.tools.removeListener(_onTools);
    super.dispose();
  }
}

/// What the chrome's buttons and menus ask of the editor screen (the
/// commands that change the screen's own state).
class EditorScreenCommands {
  const EditorScreenCommands({
    required this.back,
    required this.rename,
    required this.toggleFocus,
    required this.setStylusOnly,
    required this.openSettings,
    required this.setFlow,
    required this.pickBackground,
    required this.openSearch,
  });

  final VoidCallback back;
  final VoidCallback rename;
  final VoidCallback toggleFocus;
  final ValueChanged<bool> setStylusOnly;
  final VoidCallback openSettings;
  final ValueChanged<PageFlow> setFlow;
  final VoidCallback pickBackground;
  final VoidCallback openSearch;
}

/// The chrome around the surface, wired to one editor: the toolbar, the
/// top bar with its menus and buttons, and the page navigator. Rebuilds
/// with the document and the canvas navigation, never with the tools (the
/// toolbar's parts listen to them).
///
/// A feature that adds a top bar button or menu entry wires it here (and
/// in `editorMenuActions`).
class EditorChromeHost extends StatelessWidget {
  const EditorChromeHost({
    super.key,
    required this.session,
    required this.layout,
    required this.commands,
    required this.title,
    required this.audio,
    required this.hud,
    required this.tips,
    this.subtitle,
    this.tabs,
    this.secondPane = false,
    this.band = false,
    this.splitMenu,
    this.navigatorActivity,
    this.dimmed = false,
    this.presenting = false,
    this.split,
  });

  /// The workspace's split view (to say when its parked pane records).
  final SplitController? split;

  /// The other pane of a split view is in use: this pane's chrome dims.
  final bool dimmed;

  /// Focus mode with even the puck and the way out hidden.
  final bool presenting;

  final EditorSession session;
  final ChromeLayout layout;
  final EditorScreenCommands commands;
  final String title;

  /// The folder the notebook is filed in.
  final String? subtitle;
  final NotebookAudio audio;
  final HudController hud;
  final TipsController tips;

  /// The tab strip's tabs (null: no tab strip).
  final OpenNotebooks? tabs;
  final bool secondPane;

  /// An empty band in place of the tab strip (see [EditorTopBar.band]).
  final bool band;

  /// The "⋯" menu's split view entry (null where split view is not offered).
  final Widget? splitMenu;

  /// Pages scrolling, zooming or turning (shows the phone page indicator).
  final Listenable? navigatorActivity;

  /// What Insert ⊕ offers in this editor.
  InsertActions _insert(BuildContext context) {
    final images = session.images;
    final commands = session.commands;
    return InsertActions(
      image: () => images.pickFiles(context),
      photo: EditorImages.canUseCamera ? () => images.takePhoto(context) : null,
      pdfPages: commands == null ? null : () => commands.insertPdf(context),
      templatePage: commands == null ? null : () => commands.addPageWithTemplate(context),
    );
  }

  /// Paged notebooks: says when a PDF their pages are drawn on is missing.
  /// The standing notices: the parked pane (and its recording), a missing PDF.
  Widget? _notices() {
    final parked = split == null || secondPane ? null : ParkedPaneNotice(split: split!);
    final pdf = _missingPdfNotice();
    if (parked == null) return pdf;
    if (pdf == null) return parked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        parked,
        const SizedBox(height: Gaps.sm),
        pdf,
      ],
    );
  }

  Widget? _missingPdfNotice() {
    final doc = session.doc;
    final commands = session.commands;
    final backgrounds = session.backgrounds;
    if (doc == null || commands == null || backgrounds == null) return null;
    return Builder(
      builder: (context) => MissingPdfNotice(
        backgrounds: backgrounds,
        doc: doc,
        onRelink: (blob) => commands.relinkPdf(context, blob, backgrounds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = session.doc;
    final prefs = session.services.preferences;
    final dock = layout.dock;
    final toolbar = EditorToolbar(tools: session.tools, dock: dock, insert: _insert(context));
    final inBar = dock == ToolbarDock.inline || dock == ToolbarDock.row;
    return ListenableBuilder(
      listenable: Listenable.merge([?doc, ?session.canvasNav]),
      // Ink previews in the tool popovers show the paper being written on.
      builder: (context, _) => InkPaper(
        color: doc?.activePageData.paperColor ?? session.shared.notebook.paperColor,
        child: EditorChrome(
          layout: layout,
          hud: hud,
          tips: tips,
          dimmed: dimmed,
          notice: _notices(),
          onExitFocus: commands.toggleFocus,
          floatAt: prefs.toolbarFloat,
          onFloatMoved: (at) => prefs.toolbarFloat = at,
          presenting: presenting,
          puck: ToolPuck(tools: session.tools, undo: session.undo, insert: _insert(context)),
          puckAt: prefs.puckFloat,
          onPuckMoved: (at) => prefs.puckFloat = at,
          toolbar: toolbar,
          topBar: EditorTopBar(
            title: title,
            subtitle: subtitle,
            actions: editorMenuActions(
              context,
              session,
              onBack: commands.back,
              onRename: commands.rename,
              onFocusMode: commands.toggleFocus,
              onStylusOnly: commands.setStylusOnly,
              onSettings: commands.openSettings,
              onFlow: commands.setFlow,
              onBackground: commands.pickBackground,
              onSearch: commands.openSearch,
            ),
            undo: session.undo,
            tabs: tabs,
            audio: AudioBarButton(audio: audio),
            compactMenuItems: audioMenuItems(context, audio),
            toolbar: inBar ? toolbar : null,
            dock: dock,
            toolbarWidth: ToolbarMetrics.group(session.tools),
            splitMenu: splitMenu,
            secondPane: secondPane,
            band: band,
          ),
          navigator: editorPageNavigator(context, session),
          navigatorActivity: navigatorActivity,
        ),
      ),
    );
  }
}
