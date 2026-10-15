import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/context_menu_keys.dart';
import '../../../ui/roving_focus.dart';
import '../template_preview.dart';

/// One selectable template miniature with its name; the margin rule marks
/// the selection.
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.template,
    required this.label,
    required this.width,
    required this.selected,
    required this.onTap,
    this.onMenu,
  });

  final PageTemplate template;
  final String label;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  /// Opens the tile's menu at a global position (long press, right click).
  final ValueChanged<Offset>? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final menu = onMenu;
    // In the gallery, Tab enters at the chosen template.
    return RovingItem(
      stop: selected,
      child: ContextMenuKeys(
        onMenu: menu == null ? null : () => menu(_center(context)),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: onTap,
            onLongPress: onMenu == null ? null : () => onMenu!(_center(context)),
            onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
            borderRadius: BorderRadius.circular(Radii.xs),
            child: Padding(
              padding: const EdgeInsets.all(Gaps.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The selected template carries the margin rule along its
                  // left edge and a bold Ink name (DESIGN §0, as the sidebar
                  // marks its current row); no ring, no badge.
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ruleRoom,
                          vertical: pageRoom,
                        ),
                        // A page: square corners, a hairline edge on the sheet
                        // and the contact shadow.
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(boxShadow: Shadows.low(theme.brightness)),
                            child: TemplatePreview(template: template, width: width),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: pageRoom,
                        bottom: pageRoom,
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          width: Hairline.rule,
                          color: selected ? scheme.primary : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gaps.xs),
                  SizedBox(
                    // The name may run into the gap after the miniature, and
                    // the tile grows rather than break a word (large text).
                    width: math.max(width + labelOverhang, wordWidth(context, label)) + ruleRoom,
                    child: Padding(
                      padding: const EdgeInsets.only(left: ruleRoom),
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(context, selected: selected),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Room on each side of the miniature: the margin rule and its gap (on
  /// the 4-dp grid, UX_AUDIT R8-35).
  static const double ruleRoom = Gaps.xs;

  /// Room above and below the miniature, for its contact shadow.
  static const double pageRoom = Gaps.xxs;

  /// How far the miniature sits inside the tile: its padding and the room
  /// for the margin rule. The gallery hangs tiles out by this much so the
  /// miniatures align with the content's left edge (the rule sits in the
  /// margin, like the sidebar's).
  static const double inset = Gaps.xs + ruleRoom;

  /// How far a name may run past its miniature (into the tile's padding).
  static const double labelOverhang = ruleRoom;

  static TextStyle? _labelStyle(BuildContext context, {required bool selected}) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      color: selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
      fontWeight: selected ? AppTheme.currentWeight : FontWeight.w500,
    );
  }

  /// The width of the longest word of [label] as a selected (bold) tile
  /// shows it: the narrowest label box that never breaks a word.
  static double wordWidth(BuildContext context, String label) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final word in label.split(' ')) {
      painter
        ..text = TextSpan(text: word, style: _labelStyle(context, selected: true))
        ..layout();
      widest = math.max(widest, painter.width.ceilToDouble());
    }
    painter.dispose();
    return widest;
  }
}

Offset _center(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
}
