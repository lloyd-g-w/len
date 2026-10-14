import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/menus.dart';
import '../../../ui/theme_components.dart';
import '../notebook_audio.dart';
import '../playback_controller.dart';
import 'audio_format.dart';
import 'recordings_sheet.dart';
import 'trim_panel.dart';
import 'waveform_scrubber.dart';

/// The player for the open recording (docked in the audio strip, see
/// `AudioLayer`): title and time, a waveform
/// scrubber with ink markers, skip ±10 s, play / pause, speed, "tap ink to
/// play", the recordings list and close. Ink created later than the
/// position is faded meanwhile (see `InkReplayLayer`); keyboard control in
/// `playback_keys.dart`.
class PlaybackBar extends StatelessWidget {
  const PlaybackBar({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  Widget build(BuildContext context) {
    final playback = audio.playback;
    final recording = playback.recording;
    if (recording == null) return const SizedBox.shrink();
    if (playback.trimDraft != null) {
      return Padding(
        key: const ValueKey('playback-bar'),
        padding: _padding,
        child: TrimPanel(audio: audio),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: AppTheme.tabularFigures,
    );
    return Padding(
      key: const ValueKey('playback-bar'),
      padding: _padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gaps.xxs),
            // Title, time and Trim on one line, centred on each other.
            child: Row(
              children: [
                // Up to two lines, the whole title on hover.
                Expanded(
                  child: Tooltip(
                    message: recording.title,
                    child: Text(
                      recording.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
                const SizedBox(width: Gaps.sm),
                Text(
                  '${formatClock(playback.positionMs - playback.startMs)} / '
                  '${formatClock(recording.lengthMs)}',
                  style: small,
                ),
                IconButton(
                  tooltip: 'Trim…',
                  iconSize: Glyphs.menu,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  color: scheme.onSurfaceVariant,
                  onPressed: playback.loading ? null : playback.beginTrim,
                  icon: const Icon(Symbols.content_cut_sharp),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Gaps.xs, right: Gaps.sm),
            child: ListenableBuilder(
              listenable: audio.overviews,
              builder: (context, _) => WaveformScrubber(
                fromMs: recording.trimStartMs,
                toMs: recording.trimEndMs,
                positionMs: playback.positionMs,
                overview: audio.overviews.of(recording),
                onSeek: (ms) => unawaited(playback.seek(ms)),
              ),
            ),
          ),
          Row(
            children: [
              _skip(playback, back: true),
              IconButton.filled(
                style: ThemeComponents.inkIconButton(Theme.of(context).colorScheme),
                tooltip: playback.playing ? 'Pause (Space)' : 'Play (Space)',
                onPressed: playback.loading ? null : () => unawaited(playback.toggle()),
                icon: Icon(
                  playback.playing ? Symbols.pause_sharp : Symbols.play_arrow_sharp,
                  fill: 1,
                ),
              ),
              _skip(playback, back: false),
              const SizedBox(width: Gaps.xs),
              SpeedButton(playback: playback),
              const Spacer(),
              IconButton(
                tooltip: playback.tapToSeek
                    ? 'Tapping ink plays from it (on)'
                    : 'Tap ink to play (off)',
                isSelected: playback.tapToSeek,
                onPressed: () => playback.tapToSeek = !playback.tapToSeek,
                icon: const Icon(Symbols.touch_app_sharp),
                selectedIcon: const Icon(Symbols.touch_app_sharp, fill: 1),
                // On: the ink plate, as for a chosen tool (the accent marks
                // focus and progress only).
                style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant).copyWith(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Surfaces.pressed(scheme)
                        : Colors.transparent,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Recordings',
                onPressed: () => unawaited(showRecordingsSheet(context, audio)),
                icon: const Icon(Symbols.graphic_eq_sharp),
              ),
              IconButton(
                tooltip: 'Close player',
                onPressed: playback.close,
                icon: const Icon(Symbols.close_sharp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _padding = EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.xs, Gaps.xxs);

  Widget _skip(PlaybackController playback, {required bool back}) => IconButton(
    tooltip: back ? 'Back 10 seconds (←)' : 'Forward 10 seconds (→)',
    onPressed: playback.loading
        ? null
        : () => unawaited(
            playback.skip(back ? -PlaybackController.skipMs : PlaybackController.skipMs),
          ),
    icon: Icon(back ? Symbols.replay_10_sharp : Symbols.forward_10_sharp),
  );
}

/// Shows the playback speed ("1.5×") and offers the others.
class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MenuButton<double>(
      tooltip: 'Playback speed',
      onSelected: (rate) => unawaited(playback.setRate(rate)),
      items: () => [
        for (final rate in PlaybackController.rates)
          MenuRow(value: rate, label: formatRate(rate), checked: rate == playback.rate),
      ],
      child: Container(
        key: const ValueKey('playback-speed'),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
        child: Text(
          formatRate(playback.rate),
          style: theme.textTheme.labelLarge?.copyWith(
            color: playback.rate == 1 ? scheme.onSurfaceVariant : scheme.onSurface,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ),
    );
  }
}
