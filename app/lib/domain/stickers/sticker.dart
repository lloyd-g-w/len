import 'dart:ui';

import '../stroke.dart';
import '../surface_element.dart';

/// Reusable content — ink, text boxes, images — laid out from the origin,
/// as saved from a lasso selection (GoodNotes "Elements"). Strokes and
/// elements keep their look; their ids and surface are placeholders that
/// inserting replaces.
class StickerContent {
  StickerContent({required List<Stroke> strokes, required List<SurfaceElement> elements})
    : strokes = List.unmodifiable(strokes),
      elements = List.unmodifiable(elements);

  final List<Stroke> strokes;
  final List<SurfaceElement> elements;

  bool get isEmpty => strokes.isEmpty && elements.isEmpty;

  /// Bounds of the content: strokes with their width, elements' boxes.
  late final Rect bounds = () {
    Rect? r;
    for (final s in strokes) {
      final b = Stroke.computeBounds(s.points, s.width / 2);
      r = r == null ? b : r.expandToInclude(b);
    }
    for (final e in elements) {
      r = r == null ? e.bounds : r.expandToInclude(e.bounds);
    }
    return r ?? Rect.zero;
  }();

  /// [strokes] and [elements] moved so their [bounds] start at the origin.
  factory StickerContent.normalized(List<Stroke> strokes, List<SurfaceElement> elements) {
    final raw = StickerContent(strokes: strokes, elements: elements);
    final shift = -raw.bounds.topLeft;
    if (shift == Offset.zero) return raw;
    return StickerContent(
      strokes: [
        for (final s in strokes)
          Stroke(
            id: s.id,
            surfaceId: s.surfaceId,
            tool: s.tool,
            color: s.color,
            width: s.width,
            points: [
              for (final p in s.points) StrokePoint(p.x + shift.dx, p.y + shift.dy, p.pressure),
            ],
            createdAt: s.createdAt,
            style: s.style,
          ),
      ],
      elements: [for (final e in elements) e.copyWith(rect: e.rect.shift(shift))],
    );
  }
}

/// A saved sticker (collection `stickers`) or a built-in one.
class Sticker {
  const Sticker({
    required this.id,
    required this.name,
    required this.category,
    required this.content,
    required this.createdAt,
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// The library section it is filed under ("My stickers" by default).
  final String category;
  final StickerContent content;

  /// Milliseconds since epoch.
  final int createdAt;

  /// Built-in stickers ship with the app: not stored, not editable.
  final bool builtIn;

  Sticker copyWith({String? name, String? category}) => Sticker(
    id: id,
    name: name ?? this.name,
    category: category ?? this.category,
    content: content,
    createdAt: createdAt,
    builtIn: builtIn,
  );
}
