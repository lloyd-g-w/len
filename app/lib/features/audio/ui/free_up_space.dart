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
/// every device (trimming stays adjustable until then). The message offers
/// Undo: the dropped blobs are kept until garbage collection's grace period
/// has passed.
Future<void> freeUpSpace(BuildContext context, NotebookAudio audio, Recording recording) async {
  final bytes = audio.releasableSize(recording);
  if (bytes == null) return;
  const partMinutes = RecordingController.defaultPartMs ~/ 60000;
  final confirmed = await confirmAction(
    context,
    title: bytes > 0 ? 'Free up ${formatBytes(bytes)}?' : 'Free up space?',
    message:
        'The audio trimmed away from “${recording.title}” is deleted on all your devices, '
        'in whole parts of $partMinutes minutes (some next to the trim stays). '
        'The trim can’t be widened past what is left.',
    confirmLabel: 'Free up',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final before = await audio.freeUpSpace(recording.id);
  if (before == null || !context.mounted) return;
  showMessage(
    context,
    bytes > 0
        ? 'Freed ${formatBytes(bytes)} from “${recording.title}”'
        : 'Deleted the audio trimmed away from “${recording.title}”',
    action: SnackBarAction(label: 'Undo', onPressed: () => audio.restore(before)),
  );
}
