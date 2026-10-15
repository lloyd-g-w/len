import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../audio/recording_controller.dart';
import '../../audio/ui/audio_bar_button.dart';
import '../../audio/ui/audio_format.dart';
import '../tabs/editor_workspace.dart';
import 'shared_notebooks.dart';

/// Says, in the editor of another notebook, that a notebook no editor
/// shows is recording (see [SharedNotebooks.unattended]): a red dot (grey
/// while paused), "Recording in “Calculus”", the time, Show (opens it) and
/// Stop. Nothing otherwise.
class RecordingElsewhereNotice extends StatelessWidget {
  const RecordingElsewhereNotice({super.key, required this.notebooks});

  final SharedNotebooks notebooks;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: notebooks.unattended,
    builder: (context, shared, _) {
      if (shared == null) return const SizedBox.shrink();
      final recorder = shared.audio.recorder;
      return ListenableBuilder(
        listenable: recorder,
        builder: (context, _) => recorder.state.isActive
            ? Padding(
                // Apart from the notices below it.
                padding: const EdgeInsets.only(bottom: Gaps.sm),
                child: FloatingPanel(
                  key: const ValueKey('recording-elsewhere'),
                  padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.xs, Gaps.xs),
                  child: RecordingElsewhereRow(shared: shared),
                ),
              )
            : const SizedBox.shrink(),
      );
    },
  );
}

/// The content of [RecordingElsewhereNotice] (also the library's notice).
class RecordingElsewhereRow extends StatelessWidget {
  const RecordingElsewhereRow({super.key, required this.shared});

  final SharedNotebook shared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final audio = shared.audio;
    final recorder = audio.recorder;
    final paused = recorder.state == RecorderState.paused;
    final time = formatClock(recorder.elapsedMs);
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paused ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
            const SizedBox(width: Gaps.sm),
            Flexible(
              child: Text(
                '${paused ? 'Recording paused' : 'Recording'} in “${shared.notebook.title}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: Gaps.sm),
            Text(
              time,
              style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
            const SizedBox(width: Gaps.xs),
            TextButton(
              onPressed: () => unawaited(openNotebook(context, shared.notebook)),
              child: const Text('Show'),
            ),
            TextButton(
              onPressed: () => unawaited(stopRecording(context, audio)),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}
