import 'package:flutter/foundation.dart';

import '../../../domain/preferences.dart';
import '../document/document_layout.dart';
import '../document/page_fit.dart';
import '../document/page_overview.dart';

/// What the editor's top bar and menus can do, and the state they show.
/// Paged-only entries are null for an infinite canvas.
class EditorMenuActions {
  const EditorMenuActions({
    required this.onBack,
    required this.onRename,
    required this.onFocusMode,
    required this.stylusOnly,
    required this.onStylusOnly,
    required this.placement,
    required this.onPlacement,
    this.toolLabels = false,
    this.onToolLabels,
    this.onCustomiseToolbar,
    this.onPresent,
    required this.onSettings,
    this.onSearch,
    this.bookmarked = false,
    this.onToggleBookmark,
    this.onOverview,
    this.onPageCommand,
    this.onGoTo,
    this.onAddWithTemplate,
    this.onInsertPdf,
    this.onExport,
    this.onOutline,
    this.onAddToOutline,
    this.flow,
    this.onFlow,
    this.fit,
    this.onFit,
    this.onBackground,
    this.onFitContent,
    this.onActualSize,
    this.onBackToStart,
    this.showMinimap = false,
    this.onToggleMinimap,
  });

  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onFocusMode;
  final bool stylusOnly;
  final ValueChanged<bool> onStylusOnly;
  final ToolbarPlacement placement;
  final ValueChanged<ToolbarPlacement> onPlacement;

  /// Tool names under the toolbar's icons.
  final bool toolLabels;
  final ValueChanged<bool>? onToolLabels;

  /// Puts the toolbar into edit mode (order, hidden tools, favourites).
  final VoidCallback? onCustomiseToolbar;

  /// Starts presentation mode (no chrome, laser pointer, page navigation).
  final VoidCallback? onPresent;
  final VoidCallback onSettings;

  /// Opens in-notebook search (a menu item on phones, where the bar has
  /// no room for its button).
  final VoidCallback? onSearch;

  // Paged notebooks.
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;
  final VoidCallback? onOverview;
  final ValueChanged<PageCommand>? onPageCommand;
  final VoidCallback? onGoTo;
  final VoidCallback? onAddWithTemplate;
  final VoidCallback? onInsertPdf;

  /// Opens the export sheet.
  final VoidCallback? onExport;

  /// Opens the outline: the notebook's own and its PDFs'.
  final VoidCallback? onOutline;

  /// Adds the current page to the notebook's outline.
  final VoidCallback? onAddToOutline;
  final PageFlow? flow;
  final ValueChanged<PageFlow>? onFlow;

  /// How pages are zoomed (fit width / whole page / automatic).
  final PageFit? fit;
  final ValueChanged<PageFit>? onFit;

  // Infinite canvases.
  /// Opens the background picker (template and paper colour).
  final VoidCallback? onBackground;
  final VoidCallback? onFitContent;
  final VoidCallback? onActualSize;
  final VoidCallback? onBackToStart;
  final bool showMinimap;
  final VoidCallback? onToggleMinimap;

  bool get isPaged => onPageCommand != null;
}
