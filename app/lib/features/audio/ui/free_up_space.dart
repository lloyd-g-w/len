import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../domain/recording.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../notebook_audio.dart';
import '../recording_controller.dart';

/// "Free up 12 MB…" (or "Free up space…" when none of it is freed on this
/// device now: not here, or kept by versions): the label of the command
/// releasing [recording]'s audio outside its trim, or null when no part
/// lies wholly outside it.
String? freeUpSpaceLabel(NotebookAudio audio, Recording recording) {
  final bytes = audio.releasableSize(recording);
  if (bytes == null) return null;
  return bytes.freed > 0 ? 'Free up ${formatBytes(bytes.freed)}…' : 'Free up space…';
}

/// Asks, then drops [recording]'s parts lying wholly outside its trim on
/// every device (trimming stays adjustable until then). [context] is in
/// the recordings list, which closes so that the message's Undo can be
/// reached: the dropped blobs are kept until garbage collection's grace
/// period has passed. Audio a version of the notebook names stays while
/// one does (restoring it brings the audio back), and both messages say
/// so.
Future<void> freeUpSpace(BuildContext context, NotebookAudio audio, Recording recording) async {
  final bytes = audio.releasableSize(recording);
  if (bytes == null) return;
  final (:freed, :held) = bytes;
  const partMinutes = RecordingController.defaultPartMs ~/ 60000;
  final confirmed = await confirmAction(
    context,
    title: freed > 0 ? 'Free up ${formatBytes(freed)}?' : 'Free up space?',
    message:
        'Deletes the audio trimmed away from “${recording.title}” on all your devices, '
        'in whole $partMinutes-minute parts (a little next to the trim stays). '
        'The trim can’t be widened past what’s left${_released(held, all: freed == 0)}',
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
    held > 0
        ? 'Deleted the audio trimmed away from “${recording.title}”; '
              'older versions keep ${formatBytes(held)} of it'
        : freed > 0
        ? 'Deleted ${formatBytes(freed)} of audio from “${recording.title}”'
        : 'Deleted the audio trimmed away from “${recording.title}”',
    // A phone at large text: one line, not a sentence over half the page.
    short: 'Trimmed audio deleted',
    action: SnackBarAction(label: 'Undo', onPressed: () => audio.restore(before)),
  );
}

/// How the confirmation ends: when the space is released, and what older
/// versions keep of it ([held] bytes; [all]: all this device holds of it)
/// until they go.
String _released(int held, {required bool all}) {
  const until = 'until they are thinned out or deleted';
  if (held == 0) return ', and the space is released after a week.';
  final size = formatBytes(held);
  return all
      ? '. Older versions keep this audio ($size) $until.'
      : ', and the space is released after a week; older versions keep $size of it $until.';
}
