import 'dart:ui';

/// Moments of ink input the editor may react to: teaching a gesture once,
/// or saying why one did nothing. Unset callbacks cost nothing.
class InkEvents {
  /// A pen stroke that hold to snap would clean up (a long straight line
  /// or a closed shape) was committed as drawn. Only looked for while set.
  void Function()? shapeDrawn;

  /// A finger wrote a stroke (fingers draw). Only told while set.
  void Function()? fingerStroke;

  /// A contact started drawing: ink, erasing or a pointer tool (not a
  /// pan or zoom). The editor counts it as writing (reading, R20-6).
  void Function()? contact;

  /// A scribble to erase over text boxes or images, with no ink under it,
  /// was dropped.
  void Function()? scribbleMissed;

  /// A live stroke began on surface [surfaceId] (its points grow in
  /// `LiveInk`); live sync shows it to other devices as it is written.
  void Function(String surfaceId)? inkBegan;

  /// The live stroke [inkBegan] told of ended: committed as the strokes
  /// [strokeIds] (one, or a highlight snapped to text: one per line it
  /// covers), or (none) dropped.
  void Function(List<String> strokeIds)? inkEnded;

  /// A mouse or a stylus hovers at [world] (the active surface's
  /// coordinates) with nothing pressed, or (null) left or pressed; live
  /// sync shows it to other devices. Only told while set.
  void Function(Offset? world)? hovered;
}
