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
      return AlertDialog(
        icon: symbol == null
            ? null
            : DialogIcon(symbol, color: destructive ? scheme.error : scheme.primary),
        title: Text(title, textAlign: symbol == null ? null : TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
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
