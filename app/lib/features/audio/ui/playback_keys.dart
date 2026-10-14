import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../notebook_audio.dart';
import '../playback_controller.dart';

/// Keyboard control of the open recording, ahead of the editor's own
/// shortcuts (so ← / → skip instead of turning pages while the player is
/// open): Space plays / pauses, ← / → skip 10 s, Shift+← / → jump to the
/// previous / next burst of writing. Ignored without an open recording,
/// with Ctrl / Alt / ⌘ held, and while text is being edited. On desktops
/// the keyboard's media keys work too (see [_mediaKey]).
KeyEventResult handlePlaybackKey(NotebookAudio audio, KeyEvent event) {
  final playback = audio.playback;
  final recording = playback.recording;
  if (recording == null || event is KeyUpEvent) return KeyEventResult.ignored;
  if (_mediaKey(playback, event)) return KeyEventResult.handled;
  if (_typing()) return KeyEventResult.ignored;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  final shift = keyboard.isShiftPressed;
  if (key == LogicalKeyboardKey.space) {
    // Held down: toggle once.
    if (event is KeyDownEvent && !shift) unawaited(playback.toggle());
    return shift ? KeyEventResult.ignored : KeyEventResult.handled;
  }
  final forward = key == LogicalKeyboardKey.arrowRight;
  if (!forward && key != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
  if (!shift) {
    unawaited(playback.skip(forward ? PlaybackController.skipMs : -PlaybackController.skipMs));
    return KeyEventResult.handled;
  }
  final ink = audio.overviews.of(recording).ink;
  final position = playback.positionMs + PlaybackController.leadMs;
  final marker = forward ? ink.nextMarker(position) : ink.previousMarker(position);
  if (marker != null) {
    unawaited(playback.seek((marker - PlaybackController.leadMs).clamp(0, recording.durationMs)));
  }
  return KeyEventResult.handled;
}

/// The keyboard's media keys while Len is in front on Windows (no system
/// media controls there) and on Linux without MPRIS (with it, the desktop
/// takes the keys and sends them through MPRIS): play / pause, stop
/// (pause), next / previous and fast forward / rewind ±10 s. Android and
/// browsers hand them to their media sessions.
bool _mediaKey(PlaybackController playback, KeyEvent event) {
  if (kIsWeb || !_desktops.contains(defaultTargetPlatform)) return false;
  final key = event.logicalKey;
  final skip = _mediaSkips[key];
  if (skip != null) {
    unawaited(playback.skip(skip));
  } else if (key == LogicalKeyboardKey.mediaPlayPause) {
    if (event is KeyDownEvent) unawaited(playback.toggle());
  } else if (key == LogicalKeyboardKey.mediaPlay) {
    unawaited(playback.play());
  } else if (key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.mediaStop) {
    unawaited(playback.pause());
  } else {
    return false;
  }
  return true;
}

const _desktops = {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS};

final _mediaSkips = {
  LogicalKeyboardKey.mediaTrackNext: PlaybackController.skipMs,
  LogicalKeyboardKey.mediaFastForward: PlaybackController.skipMs,
  LogicalKeyboardKey.mediaTrackPrevious: -PlaybackController.skipMs,
  LogicalKeyboardKey.mediaRewind: -PlaybackController.skipMs,
};

/// Whether a text field (or text box being edited) has the keyboard.
bool _typing() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      (focused.widget is EditableText ||
          focused.findAncestorWidgetOfExactType<EditableText>() != null);
}
