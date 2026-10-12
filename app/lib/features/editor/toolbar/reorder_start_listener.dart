import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Starts reordering its item in the enclosing reorderable list: at once
/// (after the drag slop) with a mouse or trackpad, after a long press with a
/// finger or stylus, so touch scrolling and tapping keep working.
class ReorderStartListener extends StatelessWidget {
  const ReorderStartListener({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _pointer = {PointerDeviceKind.mouse, PointerDeviceKind.trackpad};

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      final list = SliverReorderableList.maybeOf(context);
      if (list == null) return;
      final recognizer = _pointer.contains(event.kind)
          ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
          : DelayedMultiDragGestureRecognizer(debugOwner: this);
      list.startItemDragReorder(
        index: index,
        event: event,
        recognizer: recognizer..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
      );
    },
    child: child,
  );
}
