import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// A notebook or folder being dragged in the library.
class LibraryDragItem {
  const LibraryDragItem.notebook(this.id) : isFolder = false;
  const LibraryDragItem.folder(this.id) : isFolder = true;

  final String id;
  final bool isFolder;
}

/// Accepts dragged library items; [builder] gets whether one hovers above.
class LibraryDropTarget extends StatelessWidget {
  const LibraryDropTarget({
    super.key,
    required this.onAccept,
    required this.builder,
    this.canAccept,
  });

  final ValueChanged<LibraryDragItem> onAccept;
  final bool Function(LibraryDragItem item)? canAccept;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<LibraryDragItem>(
      onWillAcceptWithDetails: (d) => canAccept?.call(d.data) ?? true,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) => builder(context, candidates.isNotEmpty),
    );
  }
}

/// The floating image under the pointer while dragging.
class DragFeedback extends StatelessWidget {
  const DragFeedback({super.key, required this.child, this.width = 120, this.height});

  final Widget child;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.04,
      child: Opacity(
        opacity: 0.92,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.cover),
            boxShadow: Shadows.high(Theme.of(context).brightness),
          ),
          // Feedback lives in the overlay, outside any Material.
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}
