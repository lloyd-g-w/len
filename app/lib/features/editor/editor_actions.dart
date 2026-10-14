import 'package:flutter/material.dart';

import '../documents/export/export_flow.dart';
import 'chrome/editor_menu_actions.dart';
import 'document/document_layout.dart';
import 'editor_session.dart';
import 'outline/outline_panel.dart';
import 'page_navigator.dart';

/// Builds what the top bar and menus offer for [session]; page commands
/// act on the current page. The editor screen supplies the actions that
/// change its own state.
EditorMenuActions editorMenuActions(
  BuildContext context,
  EditorSession session, {
  required VoidCallback onBack,
  required VoidCallback onRename,
  required VoidCallback onFocusMode,
  required ValueChanged<bool> onStylusOnly,
  required VoidCallback onSettings,
  required ValueChanged<PageFlow> onFlow,
  required VoidCallback onBackground,
  required VoidCallback onSearch,
}) {
  final prefs = session.services.preferences;
  final doc = session.doc;
  final commands = session.commands;
  final page = doc?.pages[doc.currentPage];
  final paged = doc != null && commands != null && page != null;
  final nav = session.canvasNav;
  return EditorMenuActions(
    onBack: onBack,
    onRename: onRename,
    onFocusMode: onFocusMode,
    stylusOnly: session.tools.stylusOnly,
    onStylusOnly: onStylusOnly,
    placement: prefs.toolbarPlacement,
    onPlacement: (p) => prefs.toolbarPlacement = p,
    onSettings: onSettings,
    onSearch: onSearch,
    bookmarked: page?.bookmarked ?? false,
    onOverview: paged ? () => openPageOverview(context, session) : null,
    onPageCommand: paged ? (c) => commands.run(context, c, page) : null,
    onExport: paged
        ? () => commands.export(context)
        : nav != null
        ? () => exportCanvasFlow(context, notebook: session.notebook)
        : null,
    flow: doc?.flow,
    onFlow: paged ? onFlow : null,
    fit: doc?.fit,
    onFit: paged ? doc.setFit : null,
    onBackground: nav == null ? null : onBackground,
  );
}

/// The peeking page indicator for a paged [session] (null for canvases).
Widget? editorPageNavigator(BuildContext context, EditorSession session) {
  final doc = session.doc;
  final commands = session.commands;
  // A single page has nowhere to go: no "1 / 1" pill.
  if (doc == null || commands == null || doc.pages.length < 2) return null;
  return PageNavigator(
    index: doc.currentPage,
    count: doc.pages.length,
    bookmarked: doc.pages[doc.currentPage].bookmarked,
    onOverview: () => openPageOverview(context, session),
    onGoTo: () => commands.goToPagePrompt(context, backgrounds: session.backgrounds),
  );
}

/// Opens the page overview of paged [session], with its Outline filter
/// (the notebook's and its PDFs' outlines).
Future<void> openPageOverview(BuildContext context, EditorSession session) =>
    session.commands!.openOverview(
      context,
      backgrounds: session.backgrounds,
      outline: (context, goTo) => NotebookOutlineView(session: session, onPage: goTo),
    );
