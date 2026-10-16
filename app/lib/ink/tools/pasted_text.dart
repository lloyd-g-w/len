import 'dart:ui';

import '../../core/clock.dart';
import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../elements/text_flow_chains.dart';
import '../elements/text_layout.dart';
import '../surface_model.dart';
import '../undo_history.dart';

/// Pasted text as a new text box (see `ContentTools.pasteText`).
abstract final class PastedText {
  /// Adds a box showing [data] centred on [at] (world) to [model] as one
  /// undoable edit and returns it (on a page, with [flows], the first box
  /// of the chain it runs on as). It is as wide as its text, but wraps at
  /// [maxWidth].
  static SurfaceElement add(
    TextData data, {
    required SurfaceModel model,
    required TextFlowChains? flows,
    required Offset at,
    required double maxWidth,
    required Clock clock,
  }) {
    var text = data.copyWith(autoWidth: true);
    var width = TextLayout.naturalWidth(text);
    if (width > maxWidth) {
      width = maxWidth;
      text = text.copyWith(autoWidth: false);
    }
    final height = TextLayout.heightOf(text, width);
    final element = SurfaceElement(
      id: clock.newId(),
      surfaceId: model.surfaceId,
      type: ElementType.text.name,
      rect: Rect.fromCenter(center: at, width: width, height: height),
      z: model.topZ + 1,
      createdAt: clock.nowMs(),
      data: text.toJson(),
    );
    final chains = flows;
    if (chains == null || !chains.canFlow(model.surfaceId, element)) {
      model.commit(InkEdit(addedElements: [element]));
      return element;
    }
    // On a page, a long text runs on over the next pages: from no higher
    // than where text begins on the page.
    final top = chains.pages.pagesFrom(model.surfaceId)!.first.top;
    final placed = element.rect.top >= top
        ? element
        : element.copyWith(rect: element.rect.shift(Offset(0, top - element.rect.top)));
    late SurfaceElement head;
    chains.pages.batch(() {
      final r = chains.reflow(model.surfaceId, placed, text, const []);
      head = r.head;
      model.commit(InkEdit(addedElements: [head]));
      chains.commit(r.edits);
    });
    return head;
  }
}
