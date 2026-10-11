import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../notebook_audio.dart';
import 'audio_format.dart';
import 'recordings_sheet.dart';

/// Floating player for the open recording: play / pause, position slider,
/// time, "tap ink to play" and close. Ink written later than the position
/// is faded meanwhile (see `InkReplayLayer`).
class PlaybackBar extends StatefulWidget {
  const PlaybackBar({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar> {
  /// Slider position while dragging (seeks on release).
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final playback = widget.audio.playback;
    final recording = playback.recording;
    if (recording == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = recording.durationMs.toDouble();
    final position = (_dragging ?? playback.positionMs.toDouble()).clamp(0.0, duration);
    final small = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Narrow bars (phones) leave Recordings to the menu, so the title has room.
    final roomy = MediaQuery.sizeOf(context).width >= 480;
    return FloatingPanel(
      key: const ValueKey('playback-bar'),
      padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xxs),
      child: Row(
        children: [
          IconButton(
            tooltip: playback.playing ? 'Pause' : 'Play',
            onPressed: playback.loading ? null : () => unawaited(playback.toggle()),
            icon: Icon(playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: Gaps.sm, top: Gaps.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          recording.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      const SizedBox(width: Gaps.sm),
                      Text(
                        '${formatClock(position.round())} / ${formatClock(recording.durationMs)}',
                        style: small,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: position,
                      max: duration <= 0 ? 1 : duration,
                      onChanged: (v) => setState(() => _dragging = v),
                      onChangeEnd: (v) {
                        setState(() => _dragging = null);
                        unawaited(playback.seek(v.round()));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: playback.tapToSeek
                ? 'Tapping ink plays from it (on)'
                : 'Tap ink to play (off)',
            isSelected: playback.tapToSeek,
            onPressed: () => playback.tapToSeek = !playback.tapToSeek,
            icon: const Icon(Icons.touch_app_outlined),
            selectedIcon: const Icon(Icons.touch_app_rounded),
            style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (roomy)
            IconButton(
              tooltip: 'Recordings',
              onPressed: () => unawaited(showRecordingsSheet(context, widget.audio)),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          IconButton(
            tooltip: 'Close player',
            onPressed: playback.close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
