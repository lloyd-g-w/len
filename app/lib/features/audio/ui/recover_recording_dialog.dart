import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../recording_recovery.dart';
import 'audio_format.dart';

/// Whether this run of the app has looked for interrupted recordings.
bool _offered = false;

/// Offers, once per run of the app, to recover each recording cut off by
/// the app being killed (see [RecordingRecovery]): Recover saves its
/// unsaved audio into the recording, Discard deletes it; closing the
/// dialog asks again next time.
Future<void> offerRecordingRecovery(BuildContext context, AppServices services) async {
  if (_offered) return;
  _offered = true;
  final RecordingRecovery recovery;
  final List<InterruptedRecording> found;
  try {
    final spool = await services.audio.spool?.call();
    if (spool == null) return;
    recovery = RecordingRecovery(
      spool: spool,
      blobs: services.blobs,
      repository: services.recordings,
    );
    found = await recovery.find();
  } on Object {
    return; // Never in the way of starting the app.
  }
  for (final interrupted in found) {
    final notebook = services.notebooks.get(interrupted.journal.notebookId);
    if (notebook == null) {
      await recovery.discard(interrupted);
      continue;
    }
    if (!context.mounted) return;
    final recover = await showDialog<bool>(
      context: context,
      builder: (context) => RecoverRecordingDialog(interrupted, notebookTitle: notebook.title),
    );
    if (recover == null) continue;
    if (!recover) {
      await recovery.discard(interrupted);
      continue;
    }
    final recording = await recovery.recover(interrupted);
    if (!context.mounted) return;
    showMessage(
      context,
      recording == null
          ? 'The recording could not be recovered'
          : 'Recovered “${recording.title}” (${formatClock(recording.durationMs)})',
    );
  }
}

/// Testing only: look for interrupted recordings again.
@visibleForTesting
void resetRecordingRecoveryOffer() => _offered = false;

/// Asks whether to recover an [interrupted] recording of the notebook
/// titled [notebookTitle]; pops true (recover), false (discard) or null.
class RecoverRecordingDialog extends StatelessWidget {
  const RecoverRecordingDialog(this.interrupted, {super.key, required this.notebookTitle});

  final InterruptedRecording interrupted;
  final String notebookTitle;

  @override
  Widget build(BuildContext context) {
    final title = interrupted.journal.title;
    final saved = interrupted.savedMs;
    final message = StringBuffer(
      'Len closed while recording “$title” in “$notebookTitle”. '
      '${formatClock(interrupted.unsavedMs)} of audio were not saved yet.',
    );
    if (saved > 0) message.write(' The first ${formatClock(saved)} are saved either way.');
    return AppDialog(
      icon: Icons.mic_none,
      title: 'Recover recording?',
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: dialogFormWidth),
        child: Text(message.toString(), textAlign: TextAlign.center),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Discard')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Recover')),
      ],
    );
  }
}
