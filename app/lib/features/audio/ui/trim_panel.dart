import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/recording.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/messages.dart';
import '../../../ui/theme_components.dart';
import '../notebook_audio.dart';
import '../trim_range.dart';
import 'audio_format.dart';
import 'trim_scrubber.dart';

/// Opens [recording] (paused) in the player and starts trimming it.
Future<void> trimRecording(BuildContext context, NotebookAudio audio, Recording recording) async {
  final playback = audio.playback;
  if (playback.recording?.id != recording.id) {
    if (!await playback.open(recording, autoplay: false)) {
      final error = playback.lastError;
      if (error != null && context.mounted) showMessage(context, error);
      return;
    }
  }
  playback.beginTrim();
}

/// The player while trimming (GoodNotes-style): the whole waveform with
/// start and end handles, the kept length, a preview that plays only the
/// kept audio, "Keep all" and Cancel / Save. Saving is not an editor undo
/// step (recordings are not part of a page): its message offers Undo.
class TrimPanel extends StatelessWidget {
  const TrimPanel({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  Widget build(BuildContext context) {
    final playback = audio.playback;
    final recording = playback.recording;
    final draft = playback.trimDraft;
    if (recording == null || draft == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: AppTheme.tabularFigures,
    );
    return Column(
      key: const ValueKey('trim-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Gaps.xxs, right: Gaps.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Trim “${recording.title}”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: Gaps.sm),
              Text(
                '${formatClock(draft.start)} – ${formatClock(draft.end)} '
                '(${formatClock(draft.lengthMs)})',
                key: const ValueKey('trim-range'),
                style: small,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Gaps.xs, right: Gaps.sm),
          child: ListenableBuilder(
            listenable: audio.overviews,
            builder: (context, _) => TrimScrubber(
              durationMs: recording.durationMs,
              range: draft,
              positionMs: playback.positionMs,
              // Ink of all the audio, not only of what the trim kept so far.
              overview: audio.overviews.of(
                recording.copyWith(trimStartMs: 0, trimEndMs: recording.durationMs),
              ),
              onChanged: playback.setTrimDraft,
              onSeek: (ms) => unawaited(playback.seek(ms)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Gaps.xxs, right: Gaps.sm, bottom: Gaps.xs),
          child: Row(
            children: [
              IconButton.filled(
                style: ThemeComponents.inkIconButton(Theme.of(context).colorScheme),
                tooltip: playback.playing ? 'Pause (Space)' : 'Play the kept audio (Space)',
                onPressed: playback.loading ? null : () => unawaited(playback.toggle()),
                icon: Icon(
                  playback.playing ? Symbols.pause_sharp : Symbols.play_arrow_sharp,
                  fill: 1,
                ),
              ),
              const SizedBox(width: Gaps.xs),
              TextButton(
                onPressed: draft.keepsAll(recording.durationMs)
                    ? null
                    : () => playback.setTrimDraft((start: 0, end: recording.durationMs)),
                child: const Text('Keep all'),
              ),
              const Spacer(),
              TextButton(onPressed: playback.endTrim, child: const Text('Cancel')),
              const SizedBox(width: Gaps.xs),
              FilledButton(onPressed: () => _save(context), child: const Text('Save')),
            ],
          ),
        ),
      ],
    );
  }

  void _save(BuildContext context) {
    final playback = audio.playback;
    final recording = playback.recording;
    final draft = playback.trimDraft;
    if (recording == null || draft == null) return;
    playback.endTrim();
    if (draft.start == recording.trimStartMs && draft.end == recording.trimEndMs) return;
    final before = (start: recording.trimStartMs, end: recording.trimEndMs);
    audio.trim(recording.id, draft.start, draft.end);
    unawaited(playback.seek(draft.start));
    showMessage(
      context,
      draft.keepsAll(recording.durationMs)
          ? 'Kept all of “${recording.title}”'
          : 'Trimmed “${recording.title}” to ${formatClock(draft.lengthMs)}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => audio.trim(recording.id, before.start, before.end),
      ),
    );
  }
}
