/// Shape identities in copied content: a copy's shapes are shapes of their
/// own, and its connectors attach to the copies of their targets.
///
/// A shape is named by its `Stroke.shapeId` (its `sh.o`, else its stroke
/// id) and attachments name their target by it (`sh.a[i].id`), so a copy
/// that gives strokes new ids maps every one of these names the same way.
abstract final class ShapeIds {
  /// Maps old names to new ones: the new id of a copied stroke ([copies]:
  /// old id → copy's id), else a new id made by [newId], the same for the
  /// same name each time (an origin no stroke has any more, a target not
  /// copied: nothing in the copy is that shape, so ends attached to it are
  /// ignored there as before).
  static String Function(String old) mapper(Map<String, String> copies, String Function() newId) {
    final made = <String, String>{};
    return (old) => copies[old] ?? made.putIfAbsent(old, newId);
  }

  /// Whether a stroke's encoded `style` may name shapes (an origin or
  /// attachments): a cheap test before decoding it.
  static bool mayName(String style) => style.contains('"o":') || style.contains('"a":');

  /// The decoded stroke `style` [style] with the names in its shape (`sh`:
  /// `o` and the attachments' `id`s) mapped by [idOf]; null when it names
  /// none. Anything else is kept as it is (strict parsing is the reader's).
  static Map<String, Object?>? remapStyle(Object? style, String Function(String old) idOf) {
    if (style is! Map<String, Object?>) return null;
    final sh = style['sh'];
    if (sh is! Map<String, Object?>) return null;
    final origin = sh['o'], ends = sh['a'];
    if (origin is! String && ends is! List) return null;
    Object? end(Object? e) => switch (e) {
      {'id': final String id} => {...e as Map<String, Object?>, 'id': idOf(id)},
      _ => e,
    };
    return {
      ...style,
      'sh': {
        ...sh,
        if (origin is String) 'o': idOf(origin),
        if (ends is List) 'a': [for (final e in ends) end(e)],
      },
    };
  }
}
