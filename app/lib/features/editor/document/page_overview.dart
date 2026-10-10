import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/images/element_images.dart';
import '../../../ui/app_theme.dart';
import 'page_backgrounds.dart';
import 'page_thumbnail.dart';

/// Something the user asked for on one page in the overview.
enum PageCommand {
  insertBefore('Insert page before', Icons.vertical_align_top_rounded),
  insertAfter('Insert page after', Icons.vertical_align_bottom_rounded),
  duplicate('Duplicate', Icons.copy_rounded),
  template('Change template…', Icons.grid_on_rounded),
  bookmark('Bookmark', Icons.bookmark_border_rounded),
  delete('Delete', Icons.delete_outline_rounded);

  const PageCommand(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Callbacks through which the overview edits the notebook. Each returns
/// once the change is stored; the overview then reloads its pages.
class OverviewHandlers {
  const OverviewHandlers({required this.load, required this.command, required this.move});

  /// Current pages in order.
  final List<NotebookPage> Function() load;

  /// Runs a command on a page (may show dialogs).
  final Future<void> Function(BuildContext context, PageCommand command, NotebookPage page) command;

  /// Moves a page to a new index.
  final void Function(NotebookPage page, int toIndex) move;
}

/// Grid of live page thumbnails: go to, reorder (drag), insert, duplicate,
/// delete, bookmark. Pops with the index of the page to show, if any.
class PageOverview extends StatefulWidget {
  const PageOverview({
    super.key,
    required this.handlers,
    required this.copier,
    required this.currentPage,
    this.backgrounds,
    this.images,
    this.changes,
  });

  final OverviewHandlers handlers;
  final SurfaceCopier copier;
  final int currentPage;
  final PageBackgrounds? backgrounds;

  /// Decoded bitmaps for image elements.
  final ElementImages? images;

  /// Notifies when pages change elsewhere (e.g. "Undo" in a snack bar, or
  /// a sync); the overview then reloads.
  final Listenable? changes;

  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  late final ThumbnailCache _cache = ThumbnailCache(widget.copier, images: widget.images);
  late List<NotebookPage> _pages = widget.handlers.load();
  bool _bookmarksOnly = false;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_reload);
    _cache.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _pages = widget.handlers.load());
  }

  Future<void> _run(PageCommand command, NotebookPage page) async {
    await widget.handlers.command(context, command, page);
    if (!mounted) return;
    // A duplicate's ink is new; everything else keeps its ink.
    _reload();
  }

  void _move(NotebookPage page, int toIndex) {
    widget.handlers.move(page, toIndex);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (var i = 0; i < _pages.length; i++)
        if (!_bookmarksOnly || _pages[i].bookmarked) i,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_pages.length} pages'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gaps.md),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('All')),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.bookmark_rounded),
                  label: Text('Bookmarks'),
                ),
              ],
              selected: {_bookmarksOnly},
              onSelectionChanged: (s) => setState(() => _bookmarksOnly = s.single),
            ),
          ),
        ],
      ),
      body: shown.isEmpty
          ? const Center(child: Text('No bookmarked pages yet.'))
          : GridView.builder(
              padding: const EdgeInsets.all(Gaps.xl),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: Gaps.xl,
                crossAxisSpacing: Gaps.xl,
                childAspectRatio: 0.62,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) => _PageTile(
                key: ValueKey('page-tile-${shown[i]}'),
                index: shown[i],
                page: _pages[shown[i]],
                cache: _cache,
                backgrounds: widget.backgrounds,
                current: shown[i] == widget.currentPage,
                reorderable: !_bookmarksOnly,
                onOpen: () => Navigator.of(context).pop(shown[i]),
                onCommand: (c) => _run(c, _pages[shown[i]]),
                onDrop: (from) => _move(_pages[from], shown[i]),
              ),
            ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.page,
    required this.cache,
    required this.backgrounds,
    required this.current,
    required this.reorderable,
    required this.onOpen,
    required this.onCommand,
    required this.onDrop,
  });

  final int index;
  final NotebookPage page;
  final ThumbnailCache cache;
  final PageBackgrounds? backgrounds;
  final bool current;
  final bool reorderable;
  final VoidCallback onOpen;
  final ValueChanged<PageCommand> onCommand;
  final ValueChanged<int> onDrop;

  @override
  Widget build(BuildContext context) {
    final thumb = _thumbnail(context, highlighted: false);
    final tile = Column(
      children: [
        Expanded(
          child: reorderable
              ? DragTarget<int>(
                  onWillAcceptWithDetails: (d) => d.data != index,
                  onAcceptWithDetails: (d) => onDrop(d.data),
                  builder: (context, candidates, _) => LongPressDraggable<int>(
                    data: index,
                    delay: const Duration(milliseconds: 250),
                    feedback: SizedBox(
                      width: 120,
                      child: Opacity(opacity: 0.85, child: Material(elevation: 6, child: thumb)),
                    ),
                    childWhenDragging: Opacity(opacity: 0.3, child: thumb),
                    child: _thumbnail(context, highlighted: candidates.isNotEmpty),
                  ),
                )
              : _thumbnail(context, highlighted: false),
        ),
        const SizedBox(height: Gaps.xs),
        _label(context),
      ],
    );
    return Semantics(label: 'Page ${index + 1}', button: true, child: tile);
  }

  Widget _thumbnail(BuildContext context, {required bool highlighted}) {
    final scheme = Theme.of(context).colorScheme;
    final border = highlighted || current ? scheme.primary : scheme.outlineVariant;
    return Center(
      child: GestureDetector(
        onTap: onOpen,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: border, width: highlighted || current ? 2.5 : 1),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: PageThumbnail(page: page, cache: cache, backgrounds: backgrounds),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (page.bookmarked)
          Icon(Icons.bookmark_rounded, size: 16, color: theme.colorScheme.tertiary),
        Text(
          '${index + 1}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: current ? theme.colorScheme.primary : null,
          ),
        ),
        PopupMenuButton<PageCommand>(
          tooltip: 'Page ${index + 1} options',
          icon: const Icon(Icons.more_horiz_rounded, size: 18),
          onSelected: onCommand,
          itemBuilder: (context) => [
            for (final c in PageCommand.values)
              PopupMenuItem(
                value: c,
                child: ListTile(
                  leading: Icon(
                    c == PageCommand.bookmark && page.bookmarked ? Icons.bookmark_remove : c.icon,
                  ),
                  title: Text(
                    c == PageCommand.bookmark && page.bookmarked ? 'Remove bookmark' : c.label,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
