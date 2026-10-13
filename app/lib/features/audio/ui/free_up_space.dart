import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../domain/recording.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../notebook_audio.dart';
import '../recording_controller.dart';

/// "Free up 12 MB…" (or "Free up space…" when none of it is on this
/// device): the label of the command releasing [recording]'s audio outside
/// its trim, or null when no part lies wholly outside it.
String? freeUpSpaceLabel(NotebookAudio audio, Recording recording) {
  final bytes = audio.releasableSize(recording);
  if (bytes == null) return null;
  return bytes > 0 ? 'Free up ${formatBytes(bytes)}…' : 'Free up space…';
}

/// Asks, then drops [recording]'s parts lying wholly outside its trim on
/// every device (trimming stays adjustable until then). [context] is in
/// the recordings list, which closes so that the message's Undo can be
/// reached: the dropped blobs are kept until garbage collection's grace
/// period has passed.
Future<void> freeUpSpace(BuildContext context, NotebookAudio audio, Recording recording) async {
  final bytes = audio.releasableSize(recording);
  if (bytes == null) return;
  const partMinutes = RecordingController.defaultPartMs ~/ 60000;
  final confirmed = await confirmAction(
    context,
    title: bytes > 0 ? 'Free up ${formatBytes(bytes)}?' : 'Free up space?',
    message:
        'Deletes the audio trimmed away from “${recording.title}” on all your devices, '
        'in whole $partMinutes-minute parts (a little next to the trim stays). '
        'The trim can’t be widened past what’s left, and the space is released after a week.',
    confirmLabel: 'Free up',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final navigator = Navigator.of(context);
  final host = navigator.context;
  navigator.pop();
  final before = await audio.freeUpSpace(recording.id);
  if (before == null || !host.mounted) return;
  showMessage(
    host,
    bytes > 0
        ? 'Deleted ${formatBytes(bytes)} of audio from “${recording.title}”'
        : 'Deleted the audio trimmed away from “${recording.title}”',
    action: SnackBarAction(label: 'Undo', onPressed: () => audio.restore(before)),
  );
}
