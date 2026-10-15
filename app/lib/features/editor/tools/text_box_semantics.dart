import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/tools/content_tools.dart';
import '../../../ink/viewport.dart';

/// The text boxes in view as screen-reader nodes (the canvas is painted):
/// each reads its text, in reading order, and activating one edits it.
/// Built only while a screen reader (or other semantics client) is on.
class TextBoxSemantics extends StatefulWidget {
  const TextBoxSemantics({super.key, required this.content, required this.viewport});

  final ContentTools content;
  final ViewportController viewport;

  @override
  State<TextBoxSemantics> createState() => _TextBoxSemanticsState();
}

class _TextBoxSemanticsState extends State<TextBoxSemantics> {
  bool _enabled = SemanticsBinding.instance.semanticsEnabled;

  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.addSemanticsEnabledListener(_onEnabled);
  }

  void _onEnabled() {
    final enabled = SemanticsBinding.instance.semanticsEnabled;
    if (enabled != _enabled && mounted) setState(() => _enabled = enabled);
  }

  @override
  void dispose() {
    SemanticsBinding.instance.removeSemanticsEnabledListener(_onEnabled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final content = widget.content;
    return ListenableBuilder(
      listenable: Listenable.merge([
        content.model,
        content.selection,
        content.text,
        widget.viewport,
      ]),
      builder: (context, _) {
        final model = content.model;
        final view = widget.viewport;
        final editing = content.text.current?.id;
        final boxes = [
          for (final e in model.elementsNear(view.visibleWorld))
            if (e.type == ElementType.text.name && e.id != editing) e,
        ]..sort(_readingOrder);
        return Stack(
          children: [
            for (final (i, e) in boxes.indexed)
              Positioned.fromRect(
                rect: Rect.fromPoints(
                  view.toScreen(e.bounds.topLeft),
                  view.toScreen(e.bounds.bottomRight),
                ),
                child: Semantics(
                  key: ValueKey(e.id),
                  container: true,
                  sortKey: OrdinalSortKey(i.toDouble()),
                  label: TextData.fromJson(e.data).text,
                  hint: 'Text box',
                  onTap: () => content.editText(e),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Top to bottom, then left to right.
  static int _readingOrder(SurfaceElement a, SurfaceElement b) {
    final y = a.bounds.top.compareTo(b.bounds.top);
    return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
  }
}
