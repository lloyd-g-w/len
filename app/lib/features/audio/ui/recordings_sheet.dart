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
import 'audio_bar_button.dart';
import 'audio_format.dart';
import 'trim_panel.dart';

/// Lists the notebook's recordings: tap to play, ⋯ to rename, trim (or
/// reset the trim), export or delete, long press (or "Select") to export or delete several, and a
/// button to record a new one.
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
class RecordingsList extends StatefulWidget {
  const RecordingsList({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  State<RecordingsList> createState() => _RecordingsListState();
}

class _RecordingsListState extends State<RecordingsList> {
  /// Ids of the selected recordings; null outside selection mode.
  Set<String>? _selected;

  NotebookAudio get audio => widget.audio;

  void _toggle(String id) => setState(() {
    final selected = _selected ??= {};
    if (!selected.remove(id)) selected.add(id);
    if (selected.isEmpty) _selected = null;
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([audio, audio.playback]),
      builder: (context, _) {
        final recordings = audio.recordings.reversed.toList(); // Newest first.
        _selected?.removeWhere((id) => !recordings.any((r) => r.id == id));
        if (_selected?.isEmpty ?? false) _selected = null;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Gaps.sm, 0, Gaps.sm, Gaps.lg),
            children: [
              _selected == null ? _header(context, recordings) : _selectionHeader(recordings),
              if (recordings.isEmpty) _empty(context),
              for (final r in recordings)
                _RecordingTile(
                  audio: audio,
                  recording: r,
                  selected: _selected?.contains(r.id),
                  onSelect: () => _toggle(r.id),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, List<Recording> recordings) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.sm, Gaps.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recordings', style: theme.textTheme.titleMedium),
                if (recordings.isNotEmpty)
                  Text(
                    _summary(recordings),
                    key: const ValueKey('recordings-summary'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (recordings.length > 1)
            IconButton(
              tooltip: 'Select',
              onPressed: () => setState(() => _selected = {}),
              icon: const Icon(Symbols.checklist_rounded),
            ),
          const SizedBox(width: Gaps.xs),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(startRecording(context, audio));
            },
            icon: const Icon(Symbols.mic_rounded),
            label: const Text('Record'),
          ),
        ],
      ),
    );
  }

  /// "3 recordings · 1:02:03 · 28 MB".
  String _summary(List<Recording> recordings) {
    final duration = recordings.fold(0, (sum, r) => sum + r.lengthMs);
    final sizes = [for (final r in recordings) audio.sizeOf(r)];
    final known = sizes.nonNulls.fold(0, (sum, s) => sum + s);
    final count = recordings.length == 1 ? '1 recording' : '${recordings.length} recordings';
    final size = sizes.every((s) => s == null)
        ? ''
        : ' · ${formatBytes(known)}${sizes.contains(null) ? ' on this device' : ''}';
    return '$count · ${formatClock(duration)}$size';
  }

  Widget _selectionHeader(List<Recording> recordings) {
    final selected = _selected ?? const <String>{};
    final chosen = [
      for (final r in recordings)
        if (selected.contains(r.id)) r,
    ];
    final all = selected.length == recordings.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, Gaps.sm, Gaps.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancel selection',
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Symbols.close_rounded),
          ),
          Expanded(
            child: Text(
              '${selected.length} selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: all ? 'Select none' : 'Select all',
            onPressed: () =>
                setState(() => _selected = all ? {} : {for (final r in recordings) r.id}),
            icon: Icon(all ? Symbols.deselect_rounded : Symbols.select_all_rounded),
          ),
          IconButton(
            tooltip: 'Export…',
            onPressed: chosen.isEmpty ? null : () => unawaited(_export(chosen)),
            icon: const Icon(Symbols.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Delete…',
            onPressed: chosen.isEmpty ? null : () => unawaited(_deleteAll(chosen)),
            icon: const Icon(Symbols.delete_rounded),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Text(
        'No recordings yet. Record while you write, then tap the ink '
        'to hear what was said.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Future<void> _export(List<Recording> recordings) => audio.export(context, recordings);

  Future<void> _deleteAll(List<Recording> recordings) async {
    final one = recordings.length == 1;
    final confirmed = await confirmAction(
      context,
      title: one ? 'Delete recording?' : 'Delete ${recordings.length} recordings?',
      message: one
          ? '“${recordings.single.title}” will be deleted on all your devices.'
          : 'They will be deleted on all your devices.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    audio.deleteAll({for (final r in recordings) r.id});
    if (mounted) setState(() => _selected = null);
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
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
    final details = [
      formatRecordedAt(recording.startedAt),
      formatClock(recording.lengthMs),
      if (size != null) formatBytes(size),
    ].join(' · ');
    final selecting = selected != null;
    return ListTile(
      key: ValueKey('recording-${recording.id}'),
      selected: open && !selecting,
      leading: selecting
          ? Checkbox(value: selected, onChanged: (_) => onSelect())
          : Icon(
              open && audio.playback.playing ? Symbols.graphic_eq_rounded : Symbols.play_circle_rounded,
            ),
      title: Text(recording.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: selecting
          ? onSelect
          : () {
              Navigator.of(context).pop();
              unawaited(_play(context));
            },
      onLongPress: selecting ? null : onSelect,
      trailing: selecting
          ? null
          : PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Symbols.more_vert_rounded),
              onSelected: (action) => unawaited(_run(context, action)),
              itemBuilder: (_) => [
                const MenuRow(value: 'rename', icon: Symbols.edit_rounded, label: 'Rename…'),
                const MenuRow(value: 'trim', icon: Symbols.content_cut_rounded, label: 'Trim…'),
                if (recording.trimmed)
                  const MenuRow(value: 'untrim', icon: Symbols.restore_rounded, label: 'Reset trim'),
                const MenuRow(value: 'export', icon: Symbols.ios_share_rounded, label: 'Export…'),
                const MenuRow(
                  value: 'delete',
                  icon: Symbols.delete_rounded,
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
      case 'export':
        await audio.export(context, [recording]);
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
