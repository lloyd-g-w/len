import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';

/// Progress of a long task, reported by the task and shown by
/// [runWithSteps]: what is happening and, when known, how far along.
class TaskProgress extends ChangeNotifier {
  TaskProgress(this._stage);

  String _stage;
  int? _done;
  int? _total;
  String _unit = 'page';
  String? _note;

  /// What is happening ("Reading PDF…").
  String get stage => _stage;

  /// 0–1, or null while the amount of work is unknown.
  double? get fraction {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_done ?? 0).clamp(0, total) / total;
  }

  /// "Page 3 of 12", or null while the amount of work is unknown.
  String? get detail {
    final total = _total;
    if (total == null) return _note;
    final unit = '${_unit[0].toUpperCase()}${_unit.substring(1)}';
    return '$unit ${((_done ?? 0) + 1).clamp(1, total)} of $total';
  }

  /// Starts a new stage of unknown length; [note] is shown beside it
  /// (e.g. "12 pages").
  void stageStarted(String stage, {String? note}) {
    _stage = stage;
    _note = note;
    _done = null;
    _total = null;
    notifyListeners();
  }

  /// Reports that [done] of [total] [unit]s are finished.
  void step(int done, int total, {String? stage, String unit = 'page'}) {
    if (stage != null) _stage = stage;
    _done = done;
    _total = total;
    _unit = unit;
    notifyListeners();
  }
}

/// Runs [task] behind a modal "working…" dialog and returns its result.
/// Errors are rethrown after the dialog closes.
Future<T> runWithProgress<T>(BuildContext context, String label, Future<T> Function() task) =>
    runWithSteps(context, label, (_) => task());

/// Runs [task] behind a modal dialog titled [title] that shows the stage
/// and progress the task reports through its [TaskProgress]. Errors are
/// rethrown after the dialog closes.
Future<T> runWithSteps<T>(
  BuildContext context,
  String title,
  Future<T> Function(TaskProgress progress) task, {
  String? subject,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = TaskProgress('Working…');
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        canPop: false,
        child: ProgressDialog(title: title, subject: subject, progress: progress),
      ),
    ),
  );
  try {
    return await task(progress);
  } finally {
    navigator.pop();
    progress.dispose();
  }
}

/// The dialog shown by [runWithSteps].
class ProgressDialog extends StatelessWidget {
  const ProgressDialog({super.key, required this.title, required this.progress, this.subject});

  final String title;

  /// What is being worked on, e.g. a file name.
  final String? subject;
  final TaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      icon: Icons.hourglass_top_rounded,
      title: title,
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final fraction = progress.fraction;
            final detail = progress.detail;
            return Semantics(
              liveRegion: true,
              value: fraction == null ? null : '${(fraction * 100).round()} %',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (subject != null) ...[
                    Text(
                      subject!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: Gaps.lg),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction ?? 0),
                      duration: Motion.medium,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: fraction == null ? null : value,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gaps.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progress.stage,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shows a short message at the bottom of the screen.
void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
