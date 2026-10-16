import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/sidebar_item.dart' show MarginRulePainter;
import '../../documents/overview/page_moves.dart';
import '../document/page_backgrounds.dart';
import '../document/page_thumbnail.dart';
import 'sidebar_metrics.dart';

/// One page in the page sidebar: its live thumbnail (paper at rest, the
/// bookmark ribbon on it) over its number, the page on screen marked as
/// in the overview: the margin rule beside a bold number. Tap to go there;
/// right-click (or the Menu key) for the page menu; Enter goes, Ctrl+arrows
/// move it ([onMove]). Dragging is the list's (`PageSidebar`).
class SidebarTile extends StatefulWidget {
  const SidebarTile({
    super.key,
    required this.index,
    required this.page,
    required this.current,
    required this.cache,
    required this.thumbHeight,
    required this.onTap,
    required this.onMenu,
    required this.onMove,
    this.backgrounds,
    this.pdfLabel,
    this.focusNode,
  });

  final int index;
  final NotebookPage page;

  /// The page on screen (an index): only the tiles it enters or leaves
  /// rebuild when it changes, and only their number.
  final ValueListenable<int> current;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;

  /// The height of the thumbnail's box ([SidebarMetrics.thumbHeight]).
  final double thumbHeight;

  /// "Slide 23", when the PDF's numbering differs.
  final String? pdfLabel;
  final VoidCallback onTap;

  /// Opens the page menu at a global position (null: over the tile).
  final ValueChanged<Offset?> onMenu;
  final ValueChanged<AxisDirection> onMove;
  final FocusNode? focusNode;

  @override
  State<SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<SidebarTile> {
  bool _hovered = false;

  String _label(bool current) {
    final w = widget;
    return 'Page ${w.index + 1}${w.pdfLabel == null ? '' : ', ${w.pdfLabel}'}'
        '${w.page.bookmarked ? ', bookmarked' : ''}'
        '${current ? ', current page' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    // Its own layer: the number beside it changing (the page on screen)
    // repaints no thumbnail.
    final thumb = SizedBox(
      height: w.thumbHeight,
      child: RepaintBoundary(
        child: Center(
          child: _Thumb(tile: w, hovered: _hovered),
        ),
      ),
    );
    return _IsCurrent(
      index: w.index,
      current: w.current,
      child: thumb,
      builder: (context, current, thumb) => Semantics(
        label: _label(current),
        button: true,
        excludeSemantics: true,
        customSemanticsActions: {
          ...pageMoveActions(context, w.onMove),
          const CustomSemanticsAction(label: 'Page options'): () => w.onMenu(null),
        },
        child: CallbackShortcuts(
          bindings: pageMoveBindings(w.onMove),
          child: ContextMenuKeys(
            onMenu: () => w.onMenu(null),
            child: FocusableActionDetector(
              // The copy following a drag leaves the page's focus where it is.
              focusNode: SidebarLifted.of(context) ? null : w.focusNode,
              mouseCursor: SystemMouseCursors.click,
              onShowHoverHighlight: (h) => setState(() => _hovered = h),
              actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => w.onTap())},
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: w.onTap,
                onSecondaryTapUp: (d) => w.onMenu(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    SidebarMetrics.side,
                    SidebarMetrics.gap,
                    SidebarMetrics.side,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      thumb!,
                      const SizedBox(height: Gaps.xs),
                      SizedBox(
                        height: SidebarMetrics.labelHeight(context),
                        child: _Number(tile: w, current: current),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page as paper at rest (square, contact shadow; lifted while
/// dragged), the ink overlay on hover, the bookmark ribbon.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.tile, required this.hovered});

  final SidebarTile tile;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifted = SidebarLifted.of(context);
    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: lifted ? Shadows.high(theme.brightness) : Shadows.low(theme.brightness),
          ),
          position: DecorationPosition.background,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              PageThumbnail(page: tile.page, cache: tile.cache, backgrounds: tile.backgrounds),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    color: hovered ? Surfaces.hovered(theme.colorScheme) : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (tile.page.bookmarked)
          const PositionedDirectional(
            top: 0,
            end: Gaps.sm,
            child: Icon(Symbols.bookmark_sharp, fill: 1, size: Glyphs.bar, color: Palette.bookmark),
          ),
      ],
    );
  }
}

/// The page's number (and its PDF's, when it differs); on the page on
/// screen, the margin rule and a bold number.
class _Number extends StatelessWidget {
  const _Number({required this.tile, required this.current});

  final SidebarTile tile;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        CustomPaint(
          painter: current ? MarginRulePainter(scheme.primary) : null,
          child: const SizedBox(width: Gaps.sm, height: 20),
        ),
        Text(
          '${tile.index + 1}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: current ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: current ? AppTheme.currentWeight : null,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        if (tile.pdfLabel case final pdf?)
          Expanded(
            child: Text(
              ' · $pdf',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
          ),
      ],
    );
  }
}

/// Builds with whether page [index] is [current], rebuilding only when
/// that flips (not each time the page on screen changes).
class _IsCurrent extends StatefulWidget {
  const _IsCurrent({
    required this.index,
    required this.current,
    required this.builder,
    required this.child,
  });

  final int index;
  final ValueListenable<int> current;
  final Widget Function(BuildContext context, bool current, Widget? child) builder;
  final Widget child;

  @override
  State<_IsCurrent> createState() => _IsCurrentState();
}

class _IsCurrentState extends State<_IsCurrent> {
  late bool _current = widget.current.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_changed);
  }

  @override
  void didUpdateWidget(_IsCurrent old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      old.current.removeListener(_changed);
      widget.current.addListener(_changed);
    }
    _current = widget.current.value == widget.index;
  }

  @override
  void dispose() {
    widget.current.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final current = widget.current.value == widget.index;
    if (current != _current) setState(() => _current = current);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current, widget.child);
}

/// Marks the copy of a tile that follows a drag (lifted: the high shadow).
class SidebarLifted extends InheritedWidget {
  const SidebarLifted({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarLifted>() != null;

  @override
  bool updateShouldNotify(SidebarLifted old) => false;
}
