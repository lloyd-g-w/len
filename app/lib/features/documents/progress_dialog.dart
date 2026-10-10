import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// Runs [task] behind a modal "working…" dialog and returns its result.
/// Errors are rethrown after the dialog closes.
Future<T> runWithProgress<T>(BuildContext context, String label, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator()),
              const SizedBox(width: Gaps.xl),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

/// Shows a short message at the bottom of the screen.
void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
