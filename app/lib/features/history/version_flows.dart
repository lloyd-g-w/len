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
  );
  if (name == null || !context.mounted) return;
  final saved = await services.versions.save(notebookId, name: name);
  if (!context.mounted) return;
  showMessage(context, saved == null ? 'Couldn’t save a version' : 'Version saved');
}

/// Says that [version]'s content is not on this device.
void _unavailable(BuildContext context) =>
    showMessage(context, 'This version isn’t on this device yet. Connect to sync and try again');

/// Tells open editors what a restore rewrote.
void _announce(AppServices services, String notebookId, Restored done) {
  final changes = RemoteChanges()..notebooks = true;
  if (done.pages) changes.pagesOfNotebooks.add(notebookId);
  done.surfaces.forEach(changes.reloadSurface);
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
        'version, so you can go back to it',
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
        'the notebook is now is kept as a version',
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
}) async {
  final Restored done;
  try {
    done = await restore();
  } on VersionUnavailable {
    if (context.mounted) _unavailable(context);
    return false;
  }
  _announce(services, version.notebookId, done);
  if (!context.mounted) return true;
  final before = done.before;
  showMessage(
    context,
    page ? 'Page restored to $when' : 'Restored to $when',
    action: before == null
        ? null
        : SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                _announce(services, version.notebookId, await services.versions.restore(before));
              } on VersionUnavailable {
                // Made here a moment ago: its packs are here.
              }
            },
          ),
  );
  return true;
}

/// "Copy as new notebook": writes [version] as a new notebook next to it.
Future<void> copyVersionFlow(
  BuildContext context,
  AppServices services,
  NotebookVersion version,
) async {
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
  );
  if (name == null) return;
  services.versions.rename(version.id, name);
}
