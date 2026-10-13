/// Moments of ink input the editor may react to: teaching a gesture once,
/// or saying why one did nothing. Unset callbacks cost nothing.
class InkEvents {
  /// A pen stroke that hold to snap would clean up (a long straight line
  /// or a closed shape) was committed as drawn. Only looked for while set.
  void Function()? shapeDrawn;

  /// A scribble to erase over text boxes or images, with no ink under it,
  /// was dropped.
  void Function()? scribbleMissed;
}
