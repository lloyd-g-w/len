import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../sync/remote_changes.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import 'version_labels.dart';

/// "Save version…": asks for a name and saves a named version now.
Future<void> saveVersionFlow(BuildContext context, AppServices services, String notebookId) async {
  final name = await showTextPrompt(
    context,
    title: 'Save version',
    label: 'Name',
    confirmLabel: 'Save',
    allowEmpty: true,
  );
  if (name == null || !context.mounted) return;
  final saved = await services.versions.save(notebookId, name: name);
  if (!context.mounted) return;
  showMessage(context, saved == null ? 'Couldn’t save a version' : 'Version saved');
}

/// Says that [version]'s content is not on this device.
void _unavailable(BuildContext context) =>
    showMessage(context, 'This version isn’t on this device yet. Connect to sync and try again.');

/// Tells open editors what a restore rewrote: they reload it and drop its
/// undo steps (R25-6), and those of page-level changes too if it was the
/// [whole] notebook.
void announceRestore(
  AppServices services,
  String notebookId,
  Restored done, {
  required bool whole,
}) {
  final changes = RemoteChanges()..notebooks = true;
  if (done.pages) changes.pagesOfNotebooks.add(notebookId);
  done.surfaces.forEach(changes.rewriteSurface);
  if (whole) changes.rewrittenNotebooks.add(notebookId);
  services.sync.announce(changes);
}

/// "Restore": asks, then makes the notebook what [version] holds; the
/// snack bar's Undo restores the version saved just before. [message] is
/// where the snack bar shows (the screen the history was opened from).
/// Returns whether it restored.
Future<bool> restoreVersionFlow(
  BuildContext context,
  AppServices services,
  NotebookVersion version, {
  required BuildContext message,
}) async {
  final when = VersionLabels.when(version);
  final ok = await confirmAction(
    context,
    title: 'Restore this version?',
    message:
        'The notebook goes back to how it was on $when. How it is now is kept as a '
        'version, so you can go back to it.',
    confirmLabel: 'Restore',
  );
  if (!ok || !context.mounted) return false;
  return _restore(message, services, version, () => services.versions.restore(version), when);
}

/// "Restore this page": makes page [pageId] what [version] holds of it.
Future<bool> restorePageFlow(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
  String pageId, {
  required BuildContext message,
}) async {
  final when = VersionLabels.when(version);
  final ok = await confirmAction(
    context,
    title: 'Restore this page?',
    message:
        'The page goes back to how it was on $when; the other pages stay as they are. How '
        'the notebook is now is kept as a version.',
    confirmLabel: 'Restore page',
  );
  if (!ok || !context.mounted) return false;
  return _restore(
    message,
    services,
    version,
    () => services.versions.restorePage(version, pageId),
    when,
    page: true,
  );
}

Future<bool> _restore(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
  Future<Restored> Function() restore,
  String when, {
  bool page = false,
}) => _once(
  VersionWork.restore,
  false,
  () => _restoreNow(context, services, version, restore, when, page: page),
);

Future<bool> _restoreNow(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
  Future<Restored> Function() restore,
  String when, {
  required bool page,
}) async {
  final Restored done;
  try {
    done = await restore();
  } on VersionUnavailable {
    if (context.mounted) _unavailable(context);
    return false;
  }
  announceRestore(services, version.notebookId, done, whole: !page);
  if (!context.mounted) return true;
  final before = done.before;
  showMessage(
    context,
    page ? 'Page restored to $when' : 'Restored to $when',
    action: before == null
        ? null
        : SnackBarAction(
            label: 'Undo',
            // Waits for a restore or copy started meanwhile, then runs as
            // one (the buttons say Restoring…): never refused, never twice.
            onPressed: () => _afterWork(
              () => _once(VersionWork.restore, null, () async {
                try {
                  final undone = await services.versions.restore(before);
                  announceRestore(services, version.notebookId, undone, whole: true);
                } on VersionUnavailable {
                  // Made here a moment ago: its packs are here.
                }
              }),
            ),
          ),
  );
  return true;
}

/// A restore or a copy of a version, while it runs ([versionWork]).
enum VersionWork { restore, copy }

/// The restore or copy running now (null: none). One runs at a time: a
/// second tap (on Copy, on Restore while the first writes) is ignored
/// rather than run twice, and the buttons say what runs meanwhile (a large
/// notebook takes a while).
ValueListenable<VersionWork?> get versionWork => _work;
final _work = ValueNotifier<VersionWork?>(null);

/// [versionWork], to set in tests.
@visibleForTesting
ValueNotifier<VersionWork?> get debugVersionWork => _work;

Future<T> _once<T>(VersionWork work, T idle, Future<T> Function() run) async {
  if (_work.value != null) return idle;
  _work.value = work;
  try {
    return await run();
  } finally {
    _work.value = null;
  }
}

/// Runs [run] once no restore or copy runs (at once if none does).
Future<void> _afterWork(Future<void> Function() run) async {
  while (_work.value != null) {
    final idle = Completer<void>();
    void done() {
      if (_work.value == null && !idle.isCompleted) idle.complete();
    }

    _work.addListener(done);
    try {
      await idle.future;
    } finally {
      _work.removeListener(done);
    }
  }
  await run();
}

/// "Copy as new notebook": writes [version] as a new notebook next to it.
Future<void> copyVersionFlow(BuildContext context, AppServices services, NotebookVersion version) =>
    _once(VersionWork.copy, null, () => _copy(context, services, version));

Future<void> _copy(BuildContext context, AppServices services, NotebookVersion version) async {
  final title = '${version.title} (${VersionLabels.when(version)})';
  try {
    final copy = await services.versions.copy(version, title: title);
    services.sync.announce(RemoteChanges()..notebooks = true);
    if (!context.mounted) return;
    showMessage(context, copy == null ? 'Couldn’t copy this version' : 'Copied as “$title”');
  } on VersionUnavailable {
    if (context.mounted) _unavailable(context);
  }
}

/// "Delete version": deletes [version] at once; the snack bar's Undo
/// brings it back.
void deleteVersionFlow(BuildContext context, AppServices services, NotebookVersion version) {
  services.versions.delete([version.id]);
  if (!context.mounted) return;
  showMessage(
    context,
    'Version deleted',
    action: SnackBarAction(label: 'Undo', onPressed: () => services.versions.undelete([version])),
  );
}

/// "Delete older versions…": asks, then deletes every version of the
/// notebook older than [version] (named ones too).
Future<void> deleteOlderFlow(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
) async {
  final older = services.versions.olderThan(version);
  if (older.isEmpty) return;
  final n = older.length;
  final ok = await confirmAction(
    context,
    title: 'Delete older versions?',
    message:
        '${n == 1 ? '1 version' : '$n versions'} older than ${VersionLabels.when(version)}, '
        'named ones too, are deleted on every device',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok) return;
  services.versions.delete([for (final v in older) v.id]);
}

/// "Rename…": names [version] (empty: no name).
Future<void> renameVersionFlow(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
) async {
  final name = await showTextPrompt(
    context,
    title: 'Rename version',
    label: 'Name',
    initialValue: version.name ?? '',
    confirmLabel: 'Rename',
    allowEmpty: true,
  );
  if (name == null) return;
  services.versions.rename(version.id, name);
}
