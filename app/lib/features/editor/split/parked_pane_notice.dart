import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../audio/recording_controller.dart';
import 'split_controller.dart';

/// Says, in the pane on screen, that the split view's other pane is parked
/// while there is no room for two (a tablet turned to portrait): a small
/// chip naming its notebook, with Show (swap the panes) — and, while it
/// records, that it does, with Stop. Nothing otherwise.
class ParkedPaneNotice extends StatelessWidget {
  const ParkedPaneNotice({super.key, required this.split});

  final SplitController split;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: split,
      builder: (context, _) {
        final pane = split.parked;
        if (pane == null) return const SizedBox.shrink();
        final recorder = pane.session.shared.audio.recorder;
        return ListenableBuilder(
          listenable: recorder,
          builder: (context, _) => _notice(context, pane.session.notebook.title, recorder),
        );
      },
    );
  }

  Widget _notice(BuildContext context, String title, RecordingController recorder) {
    final theme = Theme.of(context);
    final state = recorder.state;
    final recording = state != RecorderState.idle;
    final label = switch (state) {
      RecorderState.idle => '“$title” in split view',
      RecorderState.paused => 'Recording paused in “$title”',
      _ => 'Recording in “$title”',
    };
    return Semantics(
      liveRegion: recording,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: recording ? 440 : 360),
        child: FloatingPanel(
          key: ValueKey(recording ? 'parked-recording' : 'parked-pane'),
          padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.xs, Gaps.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                recording ? Symbols.mic_sharp : Symbols.vertical_split_sharp,
                fill: recording ? 1 : 0,
                size: Glyphs.menu,
                color: recording ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Gaps.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: recording ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: Gaps.xs),
              TextButton(onPressed: split.showParked, child: const Text('Show')),
              if (recording)
                TextButton(
                  onPressed: state == RecorderState.saving
                      ? null
                      : () => unawaited(recorder.stop()),
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
