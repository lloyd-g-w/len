import 'dart:math' as math;
import 'dart:ui';

import '../../domain/surface_element.dart';
import '../../domain/text/text_data.dart';
import '../surface_model.dart';
import '../undo_history.dart';
import 'text_layout.dart';

/// Hit tests inside committed text boxes (checklist ticks).
abstract final class TextHitTest {
  /// The line whose checkbox is at world point [world] in text box
  /// [element], if any.
  static int? checkboxAt(SurfaceElement element, Offset world) {
    if (element.knownType != ElementType.text) return null;
    final data = TextData.fromJson(element.data);
    if (!data.paras.any((p) => p.list == ListKind.check)) return null;
    final local = toLocal(element, world);
    final layout = TextLayout.layout(data, element.rect.width);
    final line = layout.checkboxAt(local);
    layout.dispose();
    return line;
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
  /// undoable edit.
  static void toggleChecked(SurfaceModel model, SurfaceElement element, int line) {
    final data = TextData.fromJson(element.data);
    final paras = [...data.paras];
    if (line >= paras.length) return;
    paras[line] = paras[line].copyWith(checked: !paras[line].checked);
    final next = element.copyWith(data: data.withFormatting(paras: paras).toJson(element.data));
    model.commit(InkEdit(removedElements: [element], addedElements: [next]));
  }
}
