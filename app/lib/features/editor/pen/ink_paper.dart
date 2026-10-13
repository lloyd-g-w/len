import 'package:flutter/widgets.dart';

import '../../../domain/paper.dart';

/// The paper the user writes on in this editor (the current page's colour,
/// or the canvas's), so ink previews show ink on it. Ink and paper are not
/// themed: they look the same in light and dark mode.
class InkPaper extends InheritedWidget {
  const InkPaper({super.key, required this.color, required super.child});

  final PaperColor color;

  /// The paper at [context]; white outside an editor.
  static PaperColor of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InkPaper>()?.color ?? PaperColor.white;

  /// Carries the paper at [anchor] into a popover's content (routes do not
  /// inherit from the widget that opened them).
  static WidgetBuilder carry(BuildContext anchor, WidgetBuilder builder) {
    final color = anchor.getInheritedWidgetOfExactType<InkPaper>()?.color ?? PaperColor.white;
    return (context) => InkPaper(
      color: color,
      child: Builder(builder: builder),
    );
  }

  @override
  bool updateShouldNotify(InkPaper oldWidget) => oldWidget.color != color;
}
