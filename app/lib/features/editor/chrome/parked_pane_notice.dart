import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../audio/recording_controller.dart';
import '../split/split_controller.dart';

/// Says, in the pane on screen, that the split view's other pane, parked
/// while there is no room for two (a tablet turned to portrait), is
/// recording — with Show (swap the panes) and Stop. Nothing otherwise.
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
          builder: (context, _) {
            final state = recorder.state;
            if (state == RecorderState.idle) return const SizedBox.shrink();
            final theme = Theme.of(context);
            final title = pane.session.notebook.title;
            return Semantics(
              liveRegion: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: FloatingPanel(
                  key: const ValueKey('parked-recording'),
                  padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.xs, Gaps.xs, Gaps.xs),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.mic_rounded,
                        fill: 1,
                        size: Glyphs.menu,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: Gaps.sm),
                      Expanded(
                        child: Text(
                          state == RecorderState.paused
                              ? 'Recording paused in “$title”'
                              : 'Recording in “$title”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(onPressed: split.showParked, child: const Text('Show')),
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
          },
        );
      },
    );
  }
}
