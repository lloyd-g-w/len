import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Asks to confirm an action; true if confirmed. Destructive actions get
/// a red confirm button and an error-tinted [icon] (a warning by default).
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
      final symbol = icon ?? (destructive ? Icons.warning_amber_rounded : null);
      return AppDialog(
        icon: symbol,
        iconColor: destructive ? scheme.error : null,
        title: title,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dialogFormWidth),
          child: Text(message, textAlign: symbol == null ? null : TextAlign.center),
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

/// The app's one dialog pattern (an [AlertDialog]): an optional tinted
/// [icon] centres the title (confirmations, progress, downloads), plain
/// dialogs are start-aligned. [actions] go Cancel first, the primary
/// (filled) last; when they don't fit in a row they stack, end-aligned,
/// with the primary on top and Cancel at the bottom.
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

  /// Tint of [icon] (default: the primary colour).
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
            : DialogIcon(icon!, color: iconColor ?? Theme.of(context).colorScheme.primary));
    return AlertDialog(
      icon: header,
      title: Text(
        title,
        textAlign: header == null ? null : TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: content,
      contentPadding: contentPadding,
      scrollable: scrollable,
      actions: actions.isEmpty ? null : actions,
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: 0,
    );
  }
}

/// A dialog's leading symbol in a softly tinted circle.
class DialogIcon extends StatelessWidget {
  const DialogIcon(this.icon, {super.key, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
    child: Icon(icon, color: color, size: 26),
  );
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
