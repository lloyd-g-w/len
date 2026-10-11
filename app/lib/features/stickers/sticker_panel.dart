import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/stickers/sticker.dart';
import '../../ink/images/element_images.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import 'sticker_library.dart';
import 'sticker_preview.dart';

/// Size of a sticker while it is dragged out of the panel.
const double stickerDragSize = 96;

enum _StickerAction { rename, move, delete }

/// The sticker library as a panel beside the page: categories, then a grid
/// of stickers. Tap one to put it in the middle of the screen, or drag it
/// (after a short press) to where it should go. The user's own stickers can
/// be renamed, filed elsewhere or deleted.
class StickerPanel extends StatefulWidget {
  const StickerPanel({
    super.key,
    required this.library,
    required this.onInsert,
    required this.onClose,
    this.images,
  });

  final StickerLibrary library;
  final ValueChanged<Sticker> onInsert;
  final VoidCallback onClose;
  final ElementImages? images;

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  /// The category shown; null for all.
  String? _category;

  StickerLibrary get _library => widget.library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('sticker-panel'),
      elevation: 8,
      color: scheme.surfaceContainerLow,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: _library,
        builder: (context, _) {
          final categories = _library.categories;
          if (_category != null && !categories.contains(_category)) _category = null;
          final stickers = _library.inCategory(_category);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.xs, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Stickers', style: theme.textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Close stickers',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                child: Wrap(
                  spacing: Gaps.xs,
                  runSpacing: Gaps.xs,
                  children: [
                    for (final c in [null, ...categories])
                      ChoiceChip(
                        key: ValueKey('sticker-category-${c ?? 'all'}'),
                        label: Text(c ?? 'All'),
                        selected: _category == c,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gaps.sm),
              Expanded(
                child: stickers.isEmpty
                    ? _empty(theme)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(Gaps.md, 0, Gaps.md, Gaps.md),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 104,
                          mainAxisSpacing: Gaps.sm,
                          crossAxisSpacing: Gaps.sm,
                        ),
                        itemCount: stickers.length,
                        itemBuilder: (context, i) => _tile(context, stickers[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(ThemeData theme) => Padding(
    padding: const EdgeInsets.all(Gaps.lg),
    child: Text(
      'Lasso something on a page and choose “Save as sticker” to keep it here.',
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    ),
  );

  Widget _tile(BuildContext context, Sticker sticker) {
    final scheme = Theme.of(context).colorScheme;
    final preview = StickerPreview(sticker.content, images: widget.images);
    return Tooltip(
      message: sticker.name,
      waitDuration: const Duration(milliseconds: 600),
      child: LongPressDraggable<Sticker>(
        key: ValueKey('sticker-${sticker.id}'),
        data: sticker,
        delay: const Duration(milliseconds: 150),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: const Offset(-stickerDragSize / 2, -stickerDragSize / 2),
          child: SizedBox.square(
            dimension: stickerDragSize,
            child: Opacity(
              opacity: 0.85,
              child: StickerPreview(sticker.content, images: widget.images, padding: 0),
            ),
          ),
        ),
        child: Material(
          color: Palette.paper,
          borderRadius: BorderRadius.circular(Radii.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onInsert(sticker),
            onSecondaryTapUp: sticker.builtIn
                ? null
                : (d) => unawaited(_menu(context, sticker, d.globalPosition)),
            child: Stack(
              children: [
                Positioned.fill(child: preview),
                if (!sticker.builtIn)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Sticker options',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                          foregroundColor: scheme.onSurfaceVariant,
                        ),
                        icon: const Icon(Icons.more_horiz_rounded),
                        onPressed: () => unawaited(_menu(anchor, sticker, null)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext anchor, Sticker sticker, Offset? at) async {
    final action = await showContextMenuAt<_StickerAction>(
      anchor,
      at: at,
      items: const [
        MenuRow(value: _StickerAction.rename, icon: Icons.edit_outlined, label: 'Rename…'),
        MenuRow(
          value: _StickerAction.move,
          icon: Icons.drive_file_move_outline,
          label: 'Move to category…',
        ),
        PopupMenuDivider(),
        MenuRow(
          value: _StickerAction.delete,
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _StickerAction.rename:
        final name = await showTextPrompt(
          context,
          title: 'Rename sticker',
          label: 'Name',
          initialValue: sticker.name,
          confirmLabel: 'Rename',
        );
        if (name != null && name.trim().isNotEmpty) _library.rename(sticker, name.trim());
      case _StickerAction.move:
        final category = await showTextPrompt(
          context,
          title: 'Move to category',
          label: 'Category',
          initialValue: sticker.category,
          confirmLabel: 'Move',
        );
        if (category != null && category.trim().isNotEmpty) {
          _library.move(sticker, category.trim());
        }
      case _StickerAction.delete:
        _library.delete(sticker);
        showMessage(
          context,
          'Deleted “${sticker.name}”',
          action: SnackBarAction(label: 'Undo', onPressed: () => _library.restore(sticker)),
        );
    }
  }
}
