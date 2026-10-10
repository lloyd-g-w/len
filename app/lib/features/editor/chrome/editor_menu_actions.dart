import 'package:flutter/foundation.dart';

import '../../../domain/paper.dart';
import '../../../domain/preferences.dart';
import '../../documents/export/export_flow.dart';
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
    this.canvasPaper,
    this.onCanvasPaper,
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
  final ValueChanged<ExportKind>? onExport;
  final PageFlow? flow;
  final ValueChanged<PageFlow>? onFlow;

  // Infinite canvases.
  final PaperStyle? canvasPaper;
  final ValueChanged<PaperStyle>? onCanvasPaper;

  bool get isPaged => onPageCommand != null;
}
