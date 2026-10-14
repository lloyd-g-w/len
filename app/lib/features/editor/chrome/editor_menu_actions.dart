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
    required this.onSettings,
    required this.onSearch,
    this.bookmarked = false,
    this.onOverview,
    this.onPageCommand,
    this.onExport,
    this.flow,
    this.onFlow,
    this.fit,
    this.onFit,
    this.onBackground,
  });

  final VoidCallback onBack;

  /// Renames the notebook (a tap on the title).
  final VoidCallback onRename;
  final VoidCallback onFocusMode;

  /// Palm rejection; null (Automatic) until a stylus has been seen: fingers
  /// draw until then. The menu's "Draw with finger" shows it on touch
  /// screens, and with a mouse once a stylus was seen.
  final bool? stylusOnly;
  final ValueChanged<bool> onStylusOnly;
  final ToolbarPlacement placement;
  final ValueChanged<ToolbarPlacement> onPlacement;
  final VoidCallback onSettings;

  /// Opens in-notebook search (Ctrl+F).
  final VoidCallback onSearch;

  // Paged notebooks.
  /// Whether the current page is bookmarked (the page menu's Bookmark
  /// row removes it).
  final bool bookmarked;

  /// Opens the page overview (▦ in the bar).
  final VoidCallback? onOverview;
  final ValueChanged<PageCommand>? onPageCommand;

  /// Opens the export sheet (Ctrl+E).
  final VoidCallback? onExport;
  final PageFlow? flow;
  final ValueChanged<PageFlow>? onFlow;

  /// How pages are zoomed (fit width / whole page / automatic).
  final PageFit? fit;
  final ValueChanged<PageFit>? onFit;

  // Infinite canvases.
  /// Opens the background picker (template and paper colour).
  final VoidCallback? onBackground;

  bool get isPaged => onPageCommand != null;
}
