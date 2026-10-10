import 'package:flutter/foundation.dart';

import '../../../domain/preferences.dart';
import '../document/document_layout.dart';
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
    required this.onSettings,
    this.bookmarked = false,
    this.onToggleBookmark,
    this.onOverview,
    this.onPageCommand,
    this.onGoTo,
    this.onAddWithTemplate,
    this.onInsertPdf,
    this.onExport,
    this.flow,
    this.onFlow,
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
  final VoidCallback onSettings;

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
  final PageFlow? flow;
  final ValueChanged<PageFlow>? onFlow;

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
