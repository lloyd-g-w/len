import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../domain/notebook.dart';

enum NotebookAction { rename, delete }

/// A notebook in the library grid: a coloured cover with its title below.
class NotebookCard extends StatelessWidget {
  const NotebookCard({
    super.key,
    required this.notebook,
    required this.onOpen,
    required this.onAction,
  });

  final Notebook notebook;
  final VoidCallback onOpen;
  final ValueChanged<NotebookAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Tooltip(
            message: 'Open “${notebook.title}”',
            waitDuration: const Duration(seconds: 1),
            child: Card(
              elevation: 1,
              shadowColor: Colors.black38,
              child: InkWell(
                onTap: onOpen,
                onLongPress: () => _showMenu(context),
                onSecondaryTapUp: (d) => _showMenu(context, at: d.globalPosition),
                child: _Cover(notebook: notebook),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notebook.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formatEdited(notebook.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<NotebookAction>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: onAction,
              itemBuilder: (_) => _menuItems,
            ),
          ],
        ),
      ],
    );
  }

  static const _menuItems = [
    PopupMenuItem(
      value: NotebookAction.rename,
      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rename')),
    ),
    PopupMenuItem(
      value: NotebookAction.delete,
      child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
    ),
  ];

  /// Opens the action menu at [at] (global), or at the card's centre.
  Future<void> _showMenu(BuildContext context, {Offset? at}) async {
    final box = context.findRenderObject()! as RenderBox;
    final origin = at ?? box.localToGlobal(box.size.center(Offset.zero));
    final action = await showMenu<NotebookAction>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx, origin.dy, origin.dx, origin.dy),
      items: _menuItems,
    );
    if (action != null) onAction(action);
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    final color = Color(notebook.coverColor);
    final isCanvas = notebook.kind == NotebookKind.canvas;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.12)!, Color.lerp(color, Colors.black, 0.18)!],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A bound spine for paged notebooks, a dot grid for canvases.
          if (isCanvas)
            const CustomPaint(painter: _DotGridPainter())
          else ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 14, color: Colors.black.withValues(alpha: 0.12)),
            ),
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: Colors.white.withValues(alpha: 0.22)),
            ),
          ],
          Positioned(
            right: 14,
            bottom: 14,
            child: Icon(
              isCanvas ? Icons.all_inclusive_rounded : Icons.menu_book_rounded,
              color: Colors.white.withValues(alpha: 0.85),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint dots suggesting an endless whiteboard.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const double _spacing = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var y = _spacing; y < size.height; y += _spacing) {
      for (var x = _spacing; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}
