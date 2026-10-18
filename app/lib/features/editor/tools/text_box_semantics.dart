import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/surface_element.dart';
import '../../../domain/text/text_data.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/tools/content_tools.dart';
import '../../../ink/viewport.dart';
import 'text_table_semantics.dart';

/// The text boxes in view as screen-reader nodes (the canvas is painted):
/// each reads its text, in reading order, and activating one edits it.
/// Built only while a screen reader (or other semantics client) is on.
class TextBoxSemantics extends StatefulWidget {
  const TextBoxSemantics({super.key, required this.content, required this.viewport});

  final ContentTools content;
  final ViewportController viewport;

  /// The text boxes of [model] in [view] that are nodes of their own (the
  /// one being edited is read by its editor): the page's node leaves them
  /// out of its text (R25-23).
  static Iterable<SurfaceElement> shown(SurfaceModel model, ViewportController view) =>
      model.elementsNear(view.visibleWorld).where((e) => e.type == ElementType.text.name);

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
        content.selection.settled,
        content.text,
        widget.viewport,
      ]),
      builder: (context, _) {
        final model = content.model;
        final view = widget.viewport;
        final editing = content.text.current?.id;
        final boxes = [
          for (final e in TextBoxSemantics.shown(model, view))
            if (e.id != editing) e,
        ]..sort(_readingOrder);
        return Stack(children: [for (final (i, e) in boxes.indexed) _node(e, i, view)]);
      },
    );
  }

  /// The node of box [e], [i]th in reading order: its text, and its
  /// tables' rows and cells as nodes of their own.
  Widget _node(SurfaceElement e, int i, ViewportController view) {
    final data = TextData.fromJson(e.data);
    final tables = TextTables.any(data.paras);
    final topLeft = view.toScreen(e.bounds.topLeft);
    return Positioned.fromRect(
      rect: Rect.fromPoints(topLeft, view.toScreen(e.bounds.bottomRight)),
      child: Semantics(
        key: ValueKey(e.id),
        container: true,
        explicitChildNodes: tables,
        sortKey: OrdinalSortKey(i.toDouble()),
        label: tables ? TextTableSemantics.textOutside(data) : data.text,
        hint: 'Text box',
        onTap: () => widget.content.editText(e),
        child: tables
            ? TextTableSemantics(
                data: data,
                width: e.rect.width,
                offset: view.toScreen(e.rect.topLeft) - topLeft,
                scale: view.scale,
              )
            : const SizedBox.expand(),
      ),
    );
  }

  /// Top to bottom, then left to right.
  static int _readingOrder(SurfaceElement a, SurfaceElement b) {
    final y = a.bounds.top.compareTo(b.bounds.top);
    return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
  }
}
