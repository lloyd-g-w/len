import 'package:flutter/material.dart';

import 'chrome/chrome_metrics.dart';
import 'chrome/editor_menu_actions.dart';
import 'document/document_layout.dart';
import 'document/page_overview.dart';
import 'editor_session.dart';
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
    stylusOnly: session.tools.stylusOnly ?? false,
    onStylusOnly: onStylusOnly,
    placement: prefs.toolbarPlacement,
    onPlacement: (p) => prefs.toolbarPlacement = p,
    onSettings: onSettings,
    bookmarked: page?.bookmarked ?? false,
    onToggleBookmark: paged ? () => commands.run(context, PageCommand.bookmark, page) : null,
    onOverview: paged
        ? () => commands.openOverview(context, backgrounds: session.backgrounds)
        : null,
    onPageCommand: paged ? (c) => commands.run(context, c, page) : null,
    onGoTo: paged ? () => commands.goToPagePrompt(context) : null,
    onAddWithTemplate: paged ? () => commands.addPageWithTemplate(context) : null,
    onInsertPdf: paged ? () => commands.insertPdf(context) : null,
    onExport: paged ? (kind) => commands.export(context, kind) : null,
    flow: doc?.flow,
    onFlow: paged ? onFlow : null,
    onBackground: nav == null ? null : onBackground,
    onFitContent: nav?.fitContent,
    onActualSize: nav == null ? null : () => nav.zoomTo(1),
    onBackToStart: nav?.goToOrigin,
    showMinimap: nav?.showMinimap ?? false,
    onToggleMinimap: nav?.toggleMinimap,
  );
}

/// The page navigator for a paged [session] (null for canvases). On phones
/// it also offers the page overview, which the top bar has no room for.
Widget? editorPageNavigator(BuildContext context, EditorSession session, {required double width}) {
  final doc = session.doc;
  final commands = session.commands;
  if (doc == null || commands == null) return null;
  final phone = width < ChromeMetrics.compactWidth;
  return PageNavigator(
    // Phones turn pages by scrolling (or swiping, one page at a time).
    compact: phone && doc.flow == PageFlow.continuous,
    index: doc.currentPage,
    count: doc.pages.length,
    bookmarked: doc.pages[doc.currentPage].bookmarked,
    onSelect: doc.scrollToPage,
    onAddPage: commands.addPage,
    onOverview: phone
        ? () => commands.openOverview(context, backgrounds: session.backgrounds)
        : null,
    onGoTo: () => commands.goToPagePrompt(context),
    onAddWithTemplate: () => commands.addPageWithTemplate(context),
    onInsertPdf: () => commands.insertPdf(context),
  );
}
