import 'package:flutter/material.dart';

/// Picks a colour from the page for the colour picker at [picker] (a
/// context inside it): the picker's popover or sheet steps aside while the
/// user taps the page, the colour found is passed to [apply] (while the
/// picker is still there to take it), then the picker closes. Completes
/// once done or cancelled.
typedef PickFromPage = Future<void> Function(BuildContext picker, ValueChanged<int> apply);

/// Offers an eyedropper to the colour pickers below it ([ColorChoices]
/// shows its button only under one). An [InheritedTheme], so popovers and
/// sheets opened from below it carry it along.
class EyedropperScope extends InheritedTheme {
  const EyedropperScope({super.key, required this.pick, required super.child});

  final PickFromPage pick;

  /// The eyedropper offered at [context], if any.
  static PickFromPage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EyedropperScope>()?.pick;

  @override
  Widget wrap(BuildContext context, Widget child) => EyedropperScope(pick: pick, child: child);

  @override
  bool updateShouldNotify(EyedropperScope old) => old.pick != pick;
}
