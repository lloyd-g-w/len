import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../domain/recording.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/text_prompt.dart';
import '../notebook_audio.dart';
import 'audio_bar_button.dart';
import 'audio_format.dart';

/// Lists the notebook's recordings: tap to play, ⋯ to rename or delete,
/// and a button to record a new one.
Future<void> showRecordingsSheet(BuildContext context, NotebookAudio audio) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => RecordingsList(audio: audio),
  );
}

/// The content of [showRecordingsSheet].
class RecordingsList extends StatelessWidget {
  const RecordingsList({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([audio, audio.playback]),
      builder: (context, _) {
        final recordings = audio.recordings.reversed.toList(); // Newest first.
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gaps.sm, 0, Gaps.sm, Gaps.lg),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.sm, Gaps.sm),
                child: Row(
                  children: [
                    Expanded(child: Text('Recordings', style: theme.textTheme.titleMedium)),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(startRecording(context, audio));
                      },
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Record'),
                    ),
                  ],
                ),
              ),
              if (recordings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Gaps.xl),
                  child: Text(
                    'No recordings yet. Record while you write, then tap the ink '
                    'to hear what was said.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final r in recordings) _RecordingTile(audio: audio, recording: r),
            ],
          ),
        );
      },
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.audio, required this.recording});

  final NotebookAudio audio;
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final open = audio.playback.recording?.id == recording.id;
    return ListTile(
      key: ValueKey('recording-${recording.id}'),
      selected: open,
      leading: Icon(
        open && audio.playback.playing ? Icons.graphic_eq_rounded : Icons.play_circle_rounded,
      ),
      title: Text(recording.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${formatEdited(recording.startedAt)} · ${formatClock(recording.durationMs)}'),
      onTap: () {
        Navigator.of(context).pop();
        unawaited(_play(context));
      },
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => unawaited(_run(context, action)),
        itemBuilder: (_) => const [
          MenuRow(value: 'rename', icon: Icons.edit_outlined, label: 'Rename'),
          MenuRow(
            value: 'delete',
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            destructive: true,
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await audio.play(recording)) return;
    final error = audio.playback.lastError;
    if (error != null) messenger?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _run(BuildContext context, String action) async {
    switch (action) {
      case 'rename':
        final title = await showTextPrompt(
          context,
          title: 'Rename recording',
          initialValue: recording.title,
          confirmLabel: 'Rename',
        );
        if (title != null && title.isNotEmpty) audio.rename(recording.id, title);
      case 'delete':
        final confirmed = await confirmAction(
          context,
          title: 'Delete recording?',
          message: '“${recording.title}” will be deleted on all your devices.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (confirmed) audio.delete(recording.id);
    }
  }
}
