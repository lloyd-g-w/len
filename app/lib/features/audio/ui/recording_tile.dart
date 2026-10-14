import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/format.dart';
import '../../../domain/recording.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/messages.dart';
import '../../../ui/text_prompt.dart';
import '../notebook_audio.dart';
import 'audio_format.dart';
import 'free_up_space.dart';
import 'trim_panel.dart';

/// One recording in the [RecordingsList]: tap to play, ⋯ for its menu, a
/// checkbox while selecting.
class RecordingTile extends StatelessWidget {
  const RecordingTile({
    super.key,
    required this.audio,
    required this.recording,
    required this.selected,
    required this.onSelect,
  });

  final NotebookAudio audio;
  final Recording recording;

  /// Whether the tile is selected; null outside selection mode.
  final bool? selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final open = audio.playback.recording?.id == recording.id;
    final size = audio.sizeOf(recording);
    final selecting = selected != null;
    return ListTile(
      key: ValueKey('recording-${recording.id}'),
      selected: open && !selecting,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
      leading: selecting
          ? Checkbox(value: selected, onChanged: (_) => onSelect())
          : Icon(
              open && audio.playback.playing ? Symbols.graphic_eq_sharp : Symbols.play_circle_sharp,
            ),
      title: Text(recording.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      // When, then the length at the line's end in tabular figures (separate
      // spans, not an "A · B" chain).
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              formatRecordedAt(recording.startedAt, now: audio.services.clock.nowDate()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Gaps.sm),
          Text(
            formatClock(recording.lengthMs),
            style: const TextStyle(fontFeatures: AppTheme.tabularFigures),
          ),
        ],
      ),
      onTap: selecting
          ? onSelect
          : () {
              Navigator.of(context).pop();
              unawaited(_play(context));
            },
      onLongPress: selecting ? null : onSelect,
      trailing: selecting
          ? null
          : MenuIconButton<String>(
              tooltip: 'More',
              icon: const Icon(Symbols.more_horiz_sharp),
              onSelected: (action) => unawaited(_run(context, action)),
              items: () => [
                if (size != null)
                  MenuRow(
                    value: 'size',
                    icon: Symbols.storage_sharp,
                    label: '${formatBytes(size)} on this device',
                    enabled: false,
                  ),
                const MenuRow(value: 'rename', icon: Symbols.edit_sharp, label: 'Rename…'),
                const MenuRow(value: 'trim', icon: Symbols.content_cut_sharp, label: 'Trim…'),
                if (recording.trimmed)
                  const MenuRow(value: 'untrim', icon: Symbols.restore_sharp, label: 'Reset trim'),
                if (freeUpSpaceLabel(audio, recording) case final label?)
                  MenuRow(value: 'free', icon: Symbols.delete_sweep_sharp, label: label),
                MenuRow(
                  value: 'export',
                  icon: Symbols.ios_share_sharp,
                  label: audio.canSaveToDevice ? 'Share…' : 'Export…',
                ),
                if (audio.canSaveToDevice)
                  const MenuRow(
                    value: 'save',
                    icon: Symbols.download_sharp,
                    label: 'Save to device…',
                  ),
                const MenuRow(
                  value: 'delete',
                  icon: Symbols.delete_sharp,
                  label: 'Delete…',
                  destructive: true,
                ),
              ],
            ),
    );
  }

  Future<void> _play(BuildContext context) async {
    if (await audio.play(recording)) return;
    final error = audio.playback.lastError;
    if (error != null && context.mounted) showMessage(context, error);
  }

  Future<void> _run(BuildContext context, String action) async {
    switch (action) {
      case 'rename':
        final title = await showTextPrompt(
          context,
          title: 'Rename recording',
          label: 'Name',
          initialValue: recording.title,
          confirmLabel: 'Rename',
        );
        if (title != null && title.isNotEmpty) audio.rename(recording.id, title);
      case 'trim':
        Navigator.of(context).pop();
        await trimRecording(context, audio, recording);
      case 'untrim':
        audio.trim(recording.id, 0, recording.durationMs);
      case 'free':
        await freeUpSpace(context, audio, recording);
      case 'export':
        await audio.export(context, [recording]);
      case 'save':
        await audio.export(context, [recording], toDevice: true);
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
