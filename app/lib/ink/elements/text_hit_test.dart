import 'dart:math' as math;
import 'dart:ui';

import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'shown_text_layout.dart';
import 'text_flow_chains.dart';

/// Hit tests inside committed text boxes (checklist ticks).
abstract final class TextHitTest {
  /// The line whose checkbox is at world point [world] in text box
  /// [element], if any.
  static int? checkboxAt(SurfaceElement element, Offset world) {
    if (element.knownType != ElementType.text) return null;
    final data = TextData.fromJson(element.data);
    if (!data.paras.any((p) => p.list == ListKind.check)) return null;
    final shown = ShownTextLayout.of(data, element.rect.size);
    final line = shown.layout.checkboxAt(shown.toLayout(toLocal(element, world)));
    shown.dispose();
    return line;
  }

  /// The model offset nearest world point [world] in the table cell of
  /// text box [element] it is in, if any.
  static int? cellAt(SurfaceElement element, Offset world) {
    if (element.knownType != ElementType.text) return null;
    final data = TextData.fromJson(element.data);
    if (!TextTables.any(data.paras)) return null;
    final shown = ShownTextLayout.of(data, element.rect.size);
    final hit = shown.layout.cellAt(shown.toLayout(toLocal(element, world)));
    shown.dispose();
    if (hit == null) return null;
    final start = data.text.split('\n').take(hit.line).fold(0, (n, l) => n + l.length + 1);
    return start + hit.offset;
  }

  /// [world] in [element]'s unrotated box coordinates (top left = 0, 0).
  static Offset toLocal(SurfaceElement element, Offset world) {
    final c = element.rect.center;
    final d = world - c;
    final cos = math.cos(-element.rotation), sin = math.sin(-element.rotation);
    final p = Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos) + c;
    return p - element.rect.topLeft;
  }

  /// Ticks or unticks the checklist item on [line] of [element], as one
  /// undoable edit. An item a page break splits ([flows]: its last line
  /// goes on in the box on the next page) is ticked there too.
  static void toggleChecked(
    SurfaceModel model,
    SurfaceElement element,
    int line, {
    TextFlowChains? flows,
  }) {
    final data = TextData.fromJson(element.data);
    final paras = [...data.paras];
    if (line >= paras.length) return;
    final checked = !paras[line].checked;
    paras[line] = paras[line].copyWith(checked: checked);
    final next = element.copyWith(data: data.withFormatting(paras: paras).toJson(element.data));
    final edit = InkEdit(removedElements: [element], addedElements: [next]);
    final parts = line == paras.length - 1 && flows != null
        ? _itemGoesOn(flows, model.surfaceId, element, checked)
        : const <String, InkEdit>{};
    if (parts.isEmpty) return model.commit(edit);
    flows!.pages.batch(() {
      model.commit(edit);
      flows.commit(parts);
    });
  }

  /// The edits ticking ([checked]) the parts on the next pages of the
  /// last paragraph of [element] (on [pageId]).
  static Map<String, InkEdit> _itemGoesOn(
    TextFlowChains flows,
    String pageId,
    SurfaceElement element,
    bool checked,
  ) {
    final edits = <String, InkEdit>{};
    for (final r in flows.continuationsOf(pageId, element.id)) {
      final data = TextData.fromJson(r.box.data);
      if (!(data.flow?.joined ?? false) || data.paras.isEmpty) break;
      final paras = [...data.paras];
      paras[0] = paras[0].copyWith(checked: checked);
      final next = r.box.copyWith(data: data.withFormatting(paras: paras).toJson(r.box.data));
      edits[r.pageId] = InkEdit(removedElements: [r.box], addedElements: [next]);
      if (paras.length > 1) break;
    }
    return edits;
  }
}
