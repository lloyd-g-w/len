import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_drag.dart';

/// Makes a library item draggable onto folders: immediately with a mouse,
/// after a long press on touch. A long press released without moving opens
/// the item's context menu ([onLongPressMenu]) instead.
class LibraryDraggable extends StatefulWidget {
  const LibraryDraggable({
    super.key,
    required this.item,
    required this.feedback,
    required this.onLongPressMenu,
    required this.child,
  });

  final LibraryDragItem item;
  final Widget feedback;
  final VoidCallback onLongPressMenu;
  final Widget child;

  static const _pointer = {PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
  static const _touch = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  @override
  State<LibraryDraggable> createState() => _LibraryDraggableState();
}

class _LibraryDraggableState extends State<LibraryDraggable> {
  /// How far the current touch drag has travelled.
  Offset _travelled = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final LibraryDraggable(:item, :feedback, :child) = widget;
    final placeholder = Opacity(opacity: 0.35, child: child);
    return _MouseDraggable(
      data: item,
      feedback: feedback,
      childWhenDragging: placeholder,
      child: _TouchDraggable(
        data: item,
        feedback: feedback,
        childWhenDragging: placeholder,
        hapticFeedbackOnStart: false,
        onDragStarted: () {
          _travelled = Offset.zero;
          unawaited(HapticFeedback.mediumImpact());
        },
        onDragUpdate: (d) => _travelled += d.delta,
        onDragEnd: (d) {
          // Released (nearly) where it was lifted and dropped nowhere: the
          // user only long-pressed, so show the menu.
          if (!d.wasAccepted && _travelled.distance < 24) widget.onLongPressMenu();
        },
        child: child,
      ),
    );
  }
}

/// Starts dragging as soon as a mouse or trackpad moves.
class _MouseDraggable extends Draggable<LibraryDragItem> {
  const _MouseDraggable({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      ImmediateMultiDragGestureRecognizer(supportedDevices: LibraryDraggable._pointer)
        ..onStart = onStart;
}

/// Starts dragging after a long press with a finger or stylus, so scrolling
/// and tapping keep working.
class _TouchDraggable extends LongPressDraggable<LibraryDragItem> {
  const _TouchDraggable({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.child,
    super.hapticFeedbackOnStart,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragEnd,
  });

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      DelayedMultiDragGestureRecognizer(
        delay: kLongPressTimeout,
        supportedDevices: LibraryDraggable._touch,
      )..onStart = onStart;
}
