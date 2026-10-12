import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The app's menu row: optional icon + label, red when [destructive], a
/// trailing check when [checked] (choices such as a sort order).
class MenuRow<T> extends PopupMenuItem<T> {
  const MenuRow({
    super.key,
    required T super.value,
    this.icon,
    required this.label,
    this.destructive = false,
    this.checked = false,
    super.enabled,
  }) : super(child: null, height: 44);

  final IconData? icon;
  final String label;
  final bool destructive;

  /// Marks the current choice with a check after the label.
  final bool checked;

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
        if (widget.icon case final icon?) ...[
          Icon(
            icon,
            size: 20,
            color: widget.destructive || !widget.enabled ? color : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Gaps.md),
        ],
        Expanded(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.checked) ...[
          const SizedBox(width: Gaps.md),
          Icon(Icons.check_rounded, size: 20, color: scheme.primary),
        ],
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

/// [MenuAnchor.reservedPadding] that keeps a tall menu [Gaps.sm] clear of
/// the system bars and the screen's top and bottom. (Flutter limits a menu's
/// size by it but places a menu that meets the left or right edge flush
/// against it.)
EdgeInsets menuReservedPadding(BuildContext context) =>
    MediaQuery.paddingOf(Overlay.of(context).context) + const EdgeInsets.all(Gaps.sm);
