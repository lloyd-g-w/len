import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/messages.dart';
import '../../audio/notebook_audio.dart';
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
      if (shared == null) return _StoppedNotice(notebooks: notebooks);
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
              onPressed: () => showRecordingNotebook(context, shared),
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

/// Show on a notice of a notebook recording unattended: opens it as it is
/// now — or, if it went to the trash or was deleted meanwhile (another
/// device, a path that didn't let it go), lets it go (its recording stops
/// and is saved into it) and says so, rather than opening an empty view.
void showRecordingNotebook(BuildContext context, SharedNotebook shared) {
  final services = AppScope.read(context);
  final notebook = services.notebooks.get(shared.id);
  if (notebook != null && !notebook.isTrashed) {
    unawaited(openNotebook(context, notebook));
    return;
  }
  services.sharedNotebooks.notebooksChanged();
  final title = (notebook ?? shared.notebook).title;
  showMessage(
    context,
    notebook == null
        ? '“$title” was deleted, so its recording stopped'
        : '“$title” is in the trash: its recording stopped and was saved there',
  );
}

/// Says, in an editor, that the recording of a notebook no editor showed
/// stopped when Len went to the background
/// ([SharedNotebooks.stoppedInBackground]), with Show and ✕.
class _StoppedNotice extends StatelessWidget {
  const _StoppedNotice({required this.notebooks});

  final SharedNotebooks notebooks;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: notebooks.stoppedInBackground,
    builder: (context, stop, _) {
      if (stop == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: Gaps.sm),
        child: FloatingPanel(
          key: const ValueKey('recording-stopped'),
          padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.xs, Gaps.xs),
          child: Semantics(
            liveRegion: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gaps.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            NotebookAudio.stoppedInBackground,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            backgroundStopDetail(stop),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Gaps.xs),
                  if (stop.saved != null)
                    TextButton(
                      onPressed: () => showStoppedRecording(context, stop),
                      child: const Text('Show'),
                    ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Symbols.close_sharp, size: Glyphs.menu),
                    onPressed: () => notebooks.stoppedInBackground.value = null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// "Saved as “Recording 09:30” in “Calculus”" (or why nothing was).
String backgroundStopDetail(BackgroundStop stop) => switch (stop.saved) {
  final saved? => 'Saved as “${saved.title}” in “${stop.notebook.title}”',
  null => stop.error ?? 'Nothing was saved',
};

/// Show on a [BackgroundStop] notice: opens its notebook at its
/// recordings (opening it ends the notice).
void showStoppedRecording(BuildContext context, BackgroundStop stop) {
  final services = AppScope.read(context);
  services.sharedNotebooks.stoppedInBackground.value = null;
  final notebook = services.notebooks.get(stop.notebook.id);
  if (notebook == null || notebook.isTrashed) return;
  services.openNotebooks.requestRecordings(notebook.id);
  unawaited(openNotebook(context, notebook));
}
