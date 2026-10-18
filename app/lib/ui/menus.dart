import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

export 'menu_buttons.dart';

/// The app's menu row (REDESIGN §5): an 18-dp icon in a leading slot that
/// is always reserved (so labels line up), a Label-style text, red when
/// [destructive], a trailing check when [checked] (choices such as a sort
/// order). Rows are 44 high, 48 on phones.
class MenuRow<T> extends PopupMenuItem<T> {
  const MenuRow({
    super.key,
    required T super.value,
    this.icon,
    this.leading,
    required this.label,
    this.caption,
    this.labelStyle,
    this.destructive = false,
    this.checked = false,
    this.filledIcon = false,
    this.shortcut,
    this.alternate,
    this.alternateAction,
    this.alternateHint,
    super.enabled,
  }) : assert((alternate == null) == (alternateAction == null)),
       super(child: null, height: Targets.menuRow);

  /// Chosen instead of [value] by a long press or a secondary click
  /// ("Add page after" held: with a template).
  final T? alternate;

  /// The name of the screen-reader action that chooses [alternate] (the
  /// gestures are pointer-only), e.g. "Add page with template".
  final String? alternateAction;

  /// A tooltip shown on hover saying how to reach [alternate] ("Hold or
  /// right-click for a template").
  final String? alternateHint;

  final IconData? icon;

  /// A small widget in the leading slot instead of [icon] (e.g. a colour
  /// swatch).
  final Widget? leading;
  final String label;

  /// A caption under the label (e.g. where a notebook lives).
  final String? caption;

  /// The label's style over the menu's (e.g. a font shown in itself).
  final TextStyle? labelStyle;
  final bool destructive;

  /// Marks the current choice with a check after the label.
  final bool checked;

  /// Draws [icon] filled (an active state, e.g. a favourite).
  final bool filledIcon;

  /// A keyboard shortcut hint ("Ctrl+N") after the label, shown only where
  /// a keyboard is likely (not on touch-first devices).
  final String? shortcut;

  @override
  PopupMenuItemState<T, MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends PopupMenuItemState<T, MenuRow<T>> {
  @override
  void initState() {
    super.initState();
    // A long menu (40 fonts) opens scrolled to the current choice.
    if (widget.checked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || Scrollable.maybeOf(context) == null) return;
        unawaited(
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      });
    }
  }

  @override
  Widget buildChild() {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.destructive ? scheme.error : scheme.onSurface;
    final color = widget.enabled ? base : base.withValues(alpha: 0.38);
    final row = _row(context, scheme, color);
    final alternate = widget.alternate;
    if (alternate == null || !widget.enabled) return row;
    void choose() => Navigator.pop<T>(context, alternate);
    // Pointer gestures only: the row stays one button for screen readers,
    // which offer the alternate as a custom action (merged into the row).
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: widget.alternateAction!): choose},
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onLongPress: choose,
        onSecondaryTap: choose,
        child: alternateHintTooltip(widget.alternateHint, row),
      ),
    );
  }

  Widget _row(BuildContext context, ColorScheme scheme, Color color) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: Targets.menuRowHeight(context)),
      child: Row(
        children: [
          SizedBox(
            width: widget.leading == null ? Glyphs.menu : null,
            child:
                widget.leading ??
                (widget.icon == null
                    ? null
                    : Icon(
                        widget.icon,
                        size: Glyphs.menu,
                        fill: widget.filledIcon ? 1 : 0,
                        color: widget.destructive || !widget.enabled
                            ? color
                            : scheme.onSurfaceVariant,
                      )),
          ),
          const SizedBox(width: Gaps.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.merge(widget.labelStyle)
                      .copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.caption case final caption?)
                  Text(
                    caption,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (widget.shortcut case final shortcut? when !Targets.touchFirst) ...[
            const SizedBox(width: Gaps.xl),
            Text(shortcut, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (widget.checked) ...[
            const SizedBox(width: Gaps.md),
            Icon(Symbols.check_sharp, size: Glyphs.menu, color: scheme.primary),
          ],
        ],
      ),
    );
  }
}

/// Wraps a menu row in a tooltip [hint] on how to reach its alternate (a
/// long press, a secondary click): on hover only (a long press chooses the
/// alternate), and not for screen readers (they get a custom action).
Widget alternateHintTooltip(String? hint, Widget row) => hint == null
    ? row
    : Tooltip(
        message: hint,
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: row,
      );

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
    constraints: menuConstraints(context),
  );
}

/// Shows a menu anchored under the widget of [anchor] (a button), aligned
/// with its start edge or, near the right edge of the screen, its end edge,
/// and returns the chosen value. Like a [PopupMenuButton], without its
/// Material button.
Future<T?> showMenuBelow<T>(BuildContext anchor, {required List<PopupMenuEntry<T>> items}) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay = Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final below = Offset(0, button.size.height + Gaps.xxs);
  final rect = Rect.fromPoints(
    button.localToGlobal(below, ancestor: overlay),
    button.localToGlobal(button.size.bottomRight(Offset.zero) + below, ancestor: overlay),
  );
  return showMenu<T>(
    context: anchor,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: items,
    constraints: menuConstraints(anchor),
  );
}

/// A popup menu's width: Material's 112 to 280, the most growing with
/// large text up to the screen's width less margins, so rows at 2× text
/// show their whole labels on phones too (UX_AUDIT R26-31).
BoxConstraints menuConstraints(BuildContext context) {
  const min = 112.0, max = 280.0;
  final screen = MediaQuery.sizeOf(context).width - 2 * Gaps.sm;
  final scaled = MediaQuery.textScalerOf(context).scale(max);
  return BoxConstraints(minWidth: min, maxWidth: math.max(max, math.min(scaled, screen)));
}

/// [MenuAnchor.reservedPadding] that keeps a tall menu [Gaps.sm] clear of
/// the system bars and the screen's top and bottom. (Flutter limits a menu's
/// size by it but places a menu that meets the left or right edge flush
/// against it.)
EdgeInsets menuReservedPadding(BuildContext context) =>
    MediaQuery.paddingOf(Overlay.of(context).context) + const EdgeInsets.all(Gaps.sm);

/// Keeps the [MenuAnchor] below [Gaps.sm] clear of the screen's left and
/// right edges as well. Flutter places a menu that meets one flush against
/// it, and the anchor's own padding doesn't reach the menu (its overlay
/// substitutes the overlay's), but display features do: menus avoid them
/// like a hinge. So two [Gaps.sm] strips along the sides are added as
/// features, for the anchor's menus only; [keepClear] adds strips as deep
/// as its sides, chrome the menus stay off (a menu that would overflow
/// into one moves to the anchor's other side).
class MenuEdgeMargin extends StatelessWidget {
  const MenuEdgeMargin({super.key, required this.child, this.keepClear = EdgeInsets.zero});

  final Widget child;

  /// Room along the screen's edges that menus keep out of.
  final EdgeInsets keepClear;

  /// The strips for a screen [size], with [keepClear] room at its edges.
  static List<DisplayFeature> strips(Size size, {EdgeInsets keepClear = EdgeInsets.zero}) => [
    for (final rect in [
      Rect.fromLTRB(-1, -1e5, Gaps.sm, 1e5),
      Rect.fromLTRB(size.width - Gaps.sm, -1e5, size.width + 1, 1e5),
      if (keepClear.left > 0) Rect.fromLTRB(-1, -1e5, keepClear.left, 1e5),
      if (keepClear.right > 0)
        Rect.fromLTRB(size.width - keepClear.right, -1e5, size.width + 1, 1e5),
      if (keepClear.top > 0) Rect.fromLTRB(-1e5, -1, 1e5, keepClear.top),
      if (keepClear.bottom > 0)
        Rect.fromLTRB(-1e5, size.height - keepClear.bottom, 1e5, size.height + 1),
    ])
      DisplayFeature(
        bounds: rect,
        type: DisplayFeatureType.unknown,
        state: DisplayFeatureState.unknown,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        displayFeatures: [
          ...media.displayFeatures,
          ...strips(media.size, keepClear: keepClear),
        ],
      ),
      child: child,
    );
  }
}
