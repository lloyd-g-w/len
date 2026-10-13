import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../platform/system_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/messages.dart';
import '../../editor/chrome/bar_button.dart';
import '../notebook_audio.dart';
import '../recording_controller.dart';
import 'audio_format.dart';
import 'level_meter.dart';
import 'recordings_sheet.dart';

/// The top bar's audio slot (tablets and desktops): a split button whose
/// microphone starts recording and whose ▾ lists the recordings,
/// and while recording a pill with the time, the input level, pause /
/// resume and stop.
class AudioBarButton extends StatelessWidget {
  const AudioBarButton({super.key, required this.audio});

  final NotebookAudio audio;

  @override
  Widget build(BuildContext context) {
    final recorder = audio.recorder;
    return ListenableBuilder(
      listenable: Listenable.merge([audio, recorder]),
      builder: (context, _) => AnimatedSize(
        duration: Motion.medium,
        curve: Motion.standard,
        child: switch (recorder.state) {
          RecorderState.recording || RecorderState.paused => RecordingPill(recorder: recorder),
          RecorderState.starting || RecorderState.saving => const _Busy(),
          RecorderState.idle => _idle(context),
        },
      ),
    );
  }

  /// One split button: 🎙 records; ▾ (once the notebook has recordings)
  /// opens the recordings.
  Widget _idle(BuildContext context) {
    final record = BarButton(
      tooltip: 'Record audio',
      icon: Symbols.mic_rounded,
      onPressed: () => unawaited(startRecording(context, audio)),
    );
    if (audio.recordings.isEmpty) return record;
    final list = IconButton(
      tooltip: 'Recordings',
      onPressed: () => unawaited(showRecordingsSheet(context, audio)),
      iconSize: Glyphs.bar,
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        minimumSize: const Size(20, 40),
        fixedSize: const Size(20, 40),
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(Symbols.expand_more_rounded),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [record, list]);
  }
}

/// The "⋯" menu entries on phones, where the top bar has no room for the
/// audio slot (the recording controls then float, see `AudioLayer`):
/// Record audio, and Recordings once there are any (as the bar's ▾).
List<Widget> audioMenuItems(BuildContext context, NotebookAudio audio) => [
  MenuItemButton(
    leadingIcon: const Icon(Symbols.mic_rounded),
    onPressed: () => unawaited(startRecording(context, audio)),
    child: const Text('Record audio'),
  ),
  ListenableBuilder(
    listenable: audio,
    // The editor's context: the menu's is gone once it closes.
    builder: (_, _) => audio.recordings.isEmpty
        ? const SizedBox.shrink()
        : MenuItemButton(
            leadingIcon: const Icon(Symbols.graphic_eq_rounded),
            onPressed: () => unawaited(showRecordingsSheet(context, audio)),
            child: const Text('Recordings'),
          ),
  ),
];

/// Starts recording, explaining in a snack bar why it could not.
Future<void> startRecording(BuildContext context, NotebookAudio audio) async {
  // A recording plays back over the microphone otherwise.
  if (audio.playback.playing) await audio.playback.pause();
  if (await audio.recorder.start()) return;
  final error = audio.recorder.lastError;
  if (error == null || !context.mounted) return;
  // A refused microphone: straight to where it is allowed, where possible.
  final denied = error == RecordingController.microphoneDenied && canOpenMicrophoneSettings;
  showMessage(
    context,
    error,
    action: denied
        ? SnackBarAction(label: 'Settings', onPressed: () => unawaited(openMicrophoneSettings()))
        : null,
  );
}

/// Stops recording and confirms (or explains a failure) in a snack bar.
Future<void> stopRecording(BuildContext context, RecordingController recorder) async {
  final saved = await recorder.stop();
  final error = recorder.lastError;
  if (saved != null) {
    if (context.mounted) showMessage(context, 'Saved “${saved.title}”');
  } else if (error != null) {
    if (context.mounted) showMessage(context, error);
  }
}

/// Pauses or resumes, explaining a failure in a snack bar (the pill keeps
/// showing the real state).
Future<void> togglePause(BuildContext context, RecordingController recorder) async {
  final paused = recorder.state == RecorderState.paused;
  final done = await (paused ? recorder.resume() : recorder.pause());
  final error = recorder.lastError;
  if (!done && error != null && context.mounted) showMessage(context, error);
}

/// Red dot, elapsed time, level meter (or "Paused"), pause / resume and stop.
class RecordingPill extends StatelessWidget {
  const RecordingPill({super.key, required this.recorder});

  final RecordingController recorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paused = recorder.state == RecorderState.paused;
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: scheme.onErrorContainer,
    );
    return Container(
      key: const ValueKey('recording-pill'),
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: Gaps.xs),
      padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xxs),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: paused ? scheme.onErrorContainer.withValues(alpha: 0.4) : scheme.error,
            ),
          ),
          const SizedBox(width: Gaps.sm),
          Text(formatClock(recorder.elapsedMs), style: text),
          const SizedBox(width: Gaps.sm),
          if (paused)
            Text('Paused', style: text?.copyWith(fontWeight: FontWeight.w400))
          else
            LevelMeter(level: recorder.level, color: scheme.error),
          const SizedBox(width: Gaps.xxs),
          _PillButton(
            tooltip: paused ? 'Resume recording' : 'Pause recording',
            icon: paused ? Symbols.play_arrow_rounded : Symbols.pause_rounded,
            onPressed: () => unawaited(togglePause(context, recorder)),
          ),
          _PillButton(
            tooltip: 'Stop recording',
            icon: Symbols.stop_rounded,
            onPressed: () => unawaited(stopRecording(context, recorder)),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: Glyphs.bar,
    style: IconButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
      fixedSize: const Size(32, 32),
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
    ),
    icon: Icon(icon),
  );
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 40,
    height: 40,
    child: Center(
      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );
}
