import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/cancellation.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';

export '../../domain/cancellation.dart' show CancellationToken, Cancelled;
export '../../ui/messages.dart' show showMessage;

/// Progress of a long task, reported by the task and shown by
/// [runWithSteps]: what is happening and, when known, how far along. The
/// user may cancel the task: it then stops at its next [check] (or wherever
/// it consults [token]) by throwing [Cancelled].
class TaskProgress extends ChangeNotifier {
  TaskProgress(this._stage);

  /// Asked by the task whether to stop.
  final CancellationToken token = CancellationToken();

  /// Whether the user cancelled the task.
  bool get isCancelled => token.isCancelled;

  /// Asks the task to stop.
  void cancel() {
    if (token.isCancelled) return;
    token.cancel();
    notifyListeners();
  }

  /// Throws [Cancelled] if the user cancelled the task.
  void check() => token.check();

  String _stage;
  int? _done;
  int? _total;
  String _unit = 'page';
  String? _note;

  /// Whether [detail] counts units ([step]) rather than showing the note.
  bool _counted = true;

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
    if (total == null || !_counted) return _note;
    final unit = '${_unit[0].toUpperCase()}${_unit.substring(1)}';
    return '$unit ${((_done ?? 0) + 1).clamp(1, total)} of $total';
  }

  /// Starts a new stage of unknown length; [note] is shown beside it
  /// (e.g. "12 pages"). Throws [Cancelled] if the user cancelled the task.
  void stageStarted(String stage, {String? note}) {
    check();
    _stage = stage;
    _note = note;
    _done = null;
    _total = null;
    notifyListeners();
  }

  /// Reports that the fraction [done] (0–1) of the stage is finished, when
  /// there are no units to count; throws [Cancelled] if the user cancelled
  /// the task.
  void advanced(double done) {
    check();
    _done = (done.clamp(0.0, 1.0) * 1000).round();
    _total = 1000;
    _counted = false;
    notifyListeners();
  }

  /// Reports that [done] of [total] [unit]s are finished; throws
  /// [Cancelled] if the user cancelled the task.
  void step(int done, int total, {String? stage, String unit = 'page'}) {
    check();
    if (stage != null) _stage = stage;
    _done = done;
    _total = total;
    _unit = unit;
    _counted = true;
    notifyListeners();
  }
}

/// Runs [task] behind a modal "working…" dialog and returns its result.
/// Errors are rethrown after the dialog closes. The dialog's Cancel closes
/// it at once and throws [Cancelled]; the task can't be stopped, so it
/// finishes unseen and its result (or error) is dropped. Use it only for
/// tasks without lasting effects; tasks that store something take a
/// [TaskProgress] from [runWithSteps] and [TaskProgress.check] before they do.
/// [subject] and [stage] are shown as in [runWithSteps].
Future<T> runWithProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() task, {
  String? subject,
  String stage = _working,
}) => _run(
  context,
  label,
  (_) => task(),
  subject: subject,
  stage: stage,
  cancellable: true,
  abandonOnCancel: true,
);

const _working = 'Working…';

/// Runs [task] behind a modal dialog titled [title] that shows the stage
/// and progress the task reports through its [TaskProgress]. Errors are
/// rethrown after the dialog closes. With [cancellable], the dialog has a
/// Cancel button: the task then throws [Cancelled] at its next check (it
/// must clean up after itself), which is rethrown here.
Future<T> runWithSteps<T>(
  BuildContext context,
  String title,
  Future<T> Function(TaskProgress progress) task, {
  String? subject,
  bool cancellable = false,
}) => _run(context, title, task, subject: subject, cancellable: cancellable);

/// [runWithSteps]; with [abandonOnCancel], Cancel doesn't wait for the
/// task to check: [Cancelled] is thrown at once and the task's outcome is
/// ignored (the task must not use its [TaskProgress]).
Future<T> _run<T>(
  BuildContext context,
  String title,
  Future<T> Function(TaskProgress progress) task, {
  String? subject,
  bool cancellable = false,
  String stage = _working,
  bool abandonOnCancel = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = TaskProgress(stage);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor:
        DialogTheme.of(context).barrierColor ?? Surfaces.scrim(Theme.of(context).brightness),
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (context) => PopScope(
      canPop: false,
      child: ProgressDialog(
        title: title,
        subject: subject,
        progress: progress,
        cancellable: cancellable,
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    final running = task(progress);
    if (!abandonOnCancel) return await running;
    final cancelled = Completer<T>();
    void onChange() {
      if (progress.isCancelled && !cancelled.isCompleted) {
        cancelled.completeError(const Cancelled());
      }
    }

    progress.addListener(onChange);
    // The task's outcome no longer matters once cancelled.
    unawaited(running.then<void>((_) {}, onError: (Object _) {}));
    try {
      return await Future.any([running, cancelled.future]);
    } finally {
      progress.removeListener(onChange);
    }
  } finally {
    // Only this dialog: it may be gone already (e.g. closed with the
    // editor when its notebook was deleted on another device), and then
    // popping would close whatever is on top instead.
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
    progress.dispose();
  }
}

/// The dialog shown by [runWithSteps].
class ProgressDialog extends StatelessWidget {
  const ProgressDialog({
    super.key,
    required this.title,
    required this.progress,
    this.subject,
    this.cancellable = false,
  });

  final String title;

  /// Whether a Cancel button asks the task to stop ([TaskProgress.cancel]).
  final bool cancellable;

  /// What is being worked on, e.g. a file name.
  final String? subject;
  final TaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      icon: Symbols.hourglass_top_rounded,
      title: title,
      content: ConstrainedBox(
        // As wide as the other dialogs (on phones, the screen allows less).
        constraints: const BoxConstraints.tightFor(width: dialogFormWidth),
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) {
            final fraction = progress.fraction;
            final detail = progress.detail;
            return Semantics(
              liveRegion: true,
              value: fraction == null ? null : '${(fraction * 100).round()}%',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (subject != null) ...[
                    Text(
                      subject!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: Gaps.lg),
                  ],
                  // A 2-dp ruled line with square ends (DESIGN §6).
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction ?? 0),
                    duration: Motion.medium,
                    builder: (context, value, _) =>
                        LinearProgressIndicator(value: fraction == null ? null : value),
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
                            fontFeatures: AppTheme.tabularFigures,
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
      actions: cancellable
          ? [
              ListenableBuilder(
                listenable: progress,
                builder: (context, _) => TextButton(
                  key: const ValueKey('progress-cancel'),
                  onPressed: progress.isCancelled ? null : progress.cancel,
                  child: Text(progress.isCancelled ? 'Cancelling…' : 'Cancel'),
                ),
              ),
            ]
          : const [],
    );
  }
}
