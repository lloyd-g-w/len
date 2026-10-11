import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../notebook_audio.dart';
import '../playback_controller.dart';

/// Keyboard control of the open recording, ahead of the editor's own
/// shortcuts (so ← / → skip instead of turning pages while the player is
/// open): Space plays / pauses, ← / → skip 10 s, Shift+← / → jump to the
/// previous / next burst of writing. Ignored without an open recording,
/// with Ctrl / Alt / ⌘ held, and while text is being edited.
KeyEventResult handlePlaybackKey(NotebookAudio audio, KeyEvent event) {
  final playback = audio.playback;
  final recording = playback.recording;
  if (recording == null || event is KeyUpEvent || _typing()) return KeyEventResult.ignored;
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

/// Whether a text field (or text box being edited) has the keyboard.
bool _typing() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      (focused.widget is EditableText ||
          focused.findAncestorWidgetOfExactType<EditableText>() != null);
}
