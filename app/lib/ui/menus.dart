import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A compact menu row: icon + label, red when [destructive].
class MenuRow<T> extends PopupMenuItem<T> {
  const MenuRow({
    super.key,
    required T super.value,
    required this.icon,
    required this.label,
    this.destructive = false,
    super.enabled,
  }) : super(child: null, height: 44);

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  PopupMenuItemState<T, MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends PopupMenuItemState<T, MenuRow<T>> {
  @override
  Widget buildChild() {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.destructive ? scheme.error : scheme.onSurface;
    final color = widget.enabled ? base : base.withValues(alpha: 0.38);
    return Row(
      children: [
        Icon(
          widget.icon,
          size: 20,
          color: widget.destructive || !widget.enabled ? color : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: Gaps.md),
        Flexible(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Shows a context menu at the global position [at] (or centred on the
/// widget of [context]) and returns the chosen value.
Future<T?> showContextMenuAt<T>(
  BuildContext context, {
  required List<PopupMenuEntry<T>> items,
  Offset? at,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final origin = overlay.globalToLocal(at ?? box.localToGlobal(box.size.center(Offset.zero)));
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(origin & Size.zero, Offset.zero & overlay.size),
    items: items,
  );
}
