import 'package:flutter/material.dart';

import '../audio/notebook_audio.dart';
import '../audio/ui/audio_bar_button.dart';
import 'chrome/bar_button.dart';
import 'chrome/editor_chrome.dart';
import 'chrome/editor_tips.dart';
import 'chrome/editor_top_bar.dart';
import 'chrome/gesture_hud.dart';
import 'chrome/toolbar_slot.dart';
import 'document/document_layout.dart';
import 'editor_actions.dart';
import 'editor_session.dart';
import 'editor_toolbar.dart';
import 'images/image_entry_points.dart';
import 'tabs/open_notebooks.dart';
import 'toolbar/toolbar_config.dart';
import 'toolbar/toolbar_editor.dart';

/// The toolbar's size, which the chrome's layout depends on: its height as
/// laid out (it wraps on narrow screens) and its width on one row (for
/// automatic placement; kept current as the tools change). Notifies when
/// either changes.
class ToolbarMeasure extends ChangeNotifier {
  ToolbarMeasure(this.session) {
    _width = oneRowWidth;
    session.tools.addListener(_onTools);
  }

  final EditorSession session;
  late double _width;

  /// The toolbar's measured height (null until laid out).
  double? get height => _height;
  double? _height;
  set height(double? value) {
    if (value == _height) return;
    _height = value;
    notifyListeners();
  }

  /// The toolbar's width on one row.
  double get oneRowWidth => EditorToolbar.oneRowWidth(
    session.tools,
    labels: session.services.preferences.toolbarLabels,
    config: session.services.preferences.toolbarConfig,
  );

  void _onTools() {
    final width = oneRowWidth;
    if (width == _width) return;
    _width = width;
    notifyListeners();
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
    placement: resolvePlacement(
      session.services.preferences.toolbarPlacement,
      width,
      toolbarWidth: oneRowWidth,
    ),
    toolbarHeight: _height,
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
    required this.customiseToolbar,
    required this.present,
  });

  final VoidCallback back;
  final VoidCallback rename;
  final VoidCallback toggleFocus;
  final ValueChanged<bool> setStylusOnly;
  final VoidCallback openSettings;
  final ValueChanged<PageFlow> setFlow;
  final VoidCallback pickBackground;
  final VoidCallback openSearch;

  /// Enters (true) or leaves (false) the toolbar's edit mode.
  final ValueChanged<bool> customiseToolbar;
  final VoidCallback present;
}

/// The chrome around the surface, wired to one editor: the pen toolbar
/// (or its editor while customising), the top bar with its menus and
/// buttons, and the page navigator. Rebuilds with the document, the canvas
/// navigation and the tools.
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
    required this.customising,
    required this.onToolbarHeight,
    this.subtitle,
    this.tabs,
    this.secondPane = false,
    this.band = false,
    this.splitButton,
    this.navigatorActivity,
  });

  final EditorSession session;
  final ChromeLayout layout;
  final EditorScreenCommands commands;
  final String title;

  /// The folder the notebook is filed in.
  final String? subtitle;
  final NotebookAudio audio;
  final HudController hud;
  final TipsController tips;

  /// The toolbar is in edit mode ("Customise toolbar…").
  final bool customising;
  final ValueChanged<double> onToolbarHeight;

  /// The tab strip's tabs (null: no tab strip).
  final OpenNotebooks? tabs;
  final bool secondPane;

  /// An empty band in place of the tab strip (see [EditorTopBar.band]).
  final bool band;
  final Widget? splitButton;

  /// Pages scrolling, zooming or turning (shows the phone page indicator).
  final Listenable? navigatorActivity;

  @override
  Widget build(BuildContext context) {
    final doc = session.doc;
    final prefs = session.services.preferences;
    final toolbar = customising
        ? ToolbarEditor(
            tools: session.tools,
            config: prefs.toolbarConfig,
            onChanged: (config) => prefs.toolbarConfig = config,
            onDone: () => commands.customiseToolbar(false),
          )
        : EditorToolbar(
            tools: session.tools,
            onStylusOnlyChanged: commands.setStylusOnly,
            showLabels: prefs.toolbarLabels,
            config: prefs.toolbarConfig,
          );
    return ListenableBuilder(
      listenable: Listenable.merge([?doc, ?session.canvasNav, session.tools]),
      builder: (context, _) => EditorChrome(
        layout: layout,
        hud: hud,
        tips: tips,
        onExitFocus: commands.toggleFocus,
        floatAt: prefs.toolbarFloat,
        onFloatMoved: (at) => prefs.toolbarFloat = at,
        onToolbarHeight: onToolbarHeight,
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
            onCustomiseToolbar: () => commands.customiseToolbar(true),
            onPresent: commands.present,
          ),
          undo: session.undo,
          tabs: tabs,
          audio: AudioBarButton(audio: audio),
          compactMenuItems: audioMenuItems(context, audio),
          insert: InsertImageButton(images: session.images),
          search: BarButton(
            tooltip: 'Search (Ctrl+F)',
            icon: Icons.search_rounded,
            onPressed: commands.openSearch,
          ),
          secondPane: secondPane,
          band: band,
          split: splitButton,
        ),
        navigator: editorPageNavigator(context, session, width: layout.width),
        navigatorActivity: navigatorActivity,
      ),
    );
  }
}
