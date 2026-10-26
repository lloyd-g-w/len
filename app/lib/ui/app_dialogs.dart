import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'dialog_actions.dart';

export 'dialog_actions.dart';

/// The Confirm primitive (REDESIGN §5): asks one question; true if
/// confirmed. Destructive actions get a red confirm button and an
/// error-tinted [icon] (a warning by default); other confirms have no icon.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final symbol = destructive ? icon ?? Symbols.warning_rounded : null;
      return AppDialog(
        icon: symbol,
        iconColor: destructive ? scheme.error : null,
        title: title,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dialogFormWidth),
          child: Text(message),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// The app's one dialog pattern (an [AlertDialog], an `overlay` surface of
/// radius [Radii.lg] over the scrim): a left-aligned Heading title, with a
/// tinted [icon] above it only in destructive and progress dialogs.
/// [actions] go Cancel first, the primary (filled) last; when they don't
/// fit in a row they stack full width, primary on top and Cancel at the
/// bottom ([DialogActions]).
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.icon,
    this.iconColor,
    this.leading,
    required this.title,
    this.content,
    this.actions = const [],
    this.scrollable = false,
    this.contentPadding,
  });

  /// Symbol shown in a [DialogIcon] above the title.
  final IconData? icon;

  /// Tint of [icon] (default: Graphite, like idle icons; the accent marks
  /// state only).
  final Color? iconColor;

  /// A custom header widget instead of [icon] (e.g. a live preview).
  final Widget? leading;

  final String title;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final header =
        leading ??
        (icon == null
            ? null
            : DialogIcon(
                icon!,
                color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ));
    // AlertDialog narrows its side padding as text grows, but not the
    // actions': undo that so fields, text and buttons share one edge.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final shrink = 1 - (scale.clamp(1.0, 2.0) - 1) * 2 / 3;
    double side(double v) => v / shrink;
    final content =
        (contentPadding ?? const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, Gaps.xl)).resolve(
          Directionality.of(context),
        );
    return AlertDialog(
      icon: header == null
          ? null
          : Align(alignment: AlignmentDirectional.centerStart, child: header),
      iconPadding: EdgeInsets.fromLTRB(side(Gaps.xl), side(Gaps.xl), side(Gaps.xl), Gaps.md),
      titlePadding: EdgeInsets.fromLTRB(
        side(Gaps.xl),
        header == null ? side(Gaps.xl) : 0,
        side(Gaps.xl),
        this.content == null ? 20 : 0,
      ),
      title: Text(title, textAlign: TextAlign.start, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: this.content,
      contentPadding: EdgeInsets.fromLTRB(
        side(content.left),
        content.top,
        side(content.right),
        content.bottom,
      ),
      scrollable: scrollable,
      actions: actions.isEmpty ? null : [DialogActions(children: actions)],
    );
  }
}

/// A dialog's leading symbol: the bare glyph in [color], on the title's
/// left edge (no tinted disc; DESIGN §6).
class DialogIcon extends StatelessWidget {
  const DialogIcon(this.icon, {super.key, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, color: color, size: 28);
}

/// Standard width of form dialogs (rename, folder, …).
const double dialogFormWidth = 400;

/// Keeps form dialogs a comfortable width on wide screens without
/// overflowing narrow ones.
class DialogBody extends StatelessWidget {
  const DialogBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: dialogFormWidth,
    child: Padding(
      padding: const EdgeInsets.only(top: Gaps.xs),
      child: child,
    ),
  );
}
