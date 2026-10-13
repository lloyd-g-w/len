import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_dialogs.dart';
import 'messages.dart';

/// Shows the technical [details] behind a friendly error message, to read
/// or copy (e.g. for a bug report). Messages say what happened in words;
/// this is where the raw text goes.
Future<void> showErrorDetails(
  BuildContext context, {
  required String title,
  required String details,
}) => showDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    title: title,
    scrollable: true,
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: dialogFormWidth),
      child: SelectableText(details, style: Theme.of(context).textTheme.bodySmall),
    ),
    actions: [
      TextButton(
        onPressed: () {
          unawaited(Clipboard.setData(ClipboardData(text: details)));
          showMessage(context, 'Details copied');
        },
        child: const Text('Copy'),
      ),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
    ],
  ),
);

/// A small "Details" text button that opens [showErrorDetails].
class ErrorDetailsButton extends StatelessWidget {
  const ErrorDetailsButton({super.key, required this.title, required this.details});

  final String title;
  final String details;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    onPressed: () => unawaited(showErrorDetails(context, title: title, details: details)),
    child: const Text('Details'),
  );
}
