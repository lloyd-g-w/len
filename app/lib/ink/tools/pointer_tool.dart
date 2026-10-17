import 'dart:ui';

/// One pointer sample handed to a [PointerTool].
class ToolPointer {
  const ToolPointer({
    required this.screen,
    required this.world,
    this.pressure = 0.5,
    this.kind = PointerDeviceKind.touch,
  });

  /// Position in the surface widget (logical pixels).
  final Offset screen;

  /// Position in world coordinates.
  final Offset world;

  /// Normalised pressure (0.5 without a stylus).
  final double pressure;

  /// What is pointing (a finger, pen or mouse): how far handles reach.
  final PointerDeviceKind kind;
}

/// A tool driven by the drawing pointer (pen, mouse or drawing finger)
/// instead of producing ink: lasso, shapes, text and the laser pointer.
///
/// [InkInputController] routes one pointer at a time to the active tool;
/// navigation, palm rejection and the stylus eraser are handled before.
abstract interface class PointerTool {
  void down(ToolPointer p);
  void move(ToolPointer p);

  /// The pointer lifted (at its last [move] position).
  void up();

  /// The gesture was abandoned (e.g. it turned into a pinch).
  void cancel();
}
