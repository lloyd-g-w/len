import 'dart:math' as math;
import 'dart:ui';

/// Element types known to this version. Stored by [name]; never rename.
///
/// Elements of other types (from newer clients) are kept and synced as-is
/// but not rendered.
enum ElementType {
  text,

  /// A bitmap stored as a blob (`ImageData`: blob hash, natural size, crop).
  image,

  /// A tappable region leading to a page or a web address (`LinkTarget`);
  /// shown only by the editor, never drawn into the content.
  link;

  static ElementType? parse(String value) {
    for (final t in values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// A non-ink object placed on a surface (a text box or an image).
///
/// Geometry is generic — a [rect] in world units, rotated by [rotation]
/// radians about its centre — and everything type-specific lives in the
/// opaque [data] map, so new element types need no schema change.
///
/// Unlike strokes, elements keep their id when edited (typing into a text
/// box rewrites the same record); edits replace the whole value.
class SurfaceElement {
  SurfaceElement({
    required this.id,
    required this.surfaceId,
    required this.type,
    required this.rect,
    this.rotation = 0,
    required this.z,
    required this.createdAt,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(data),
       bounds = rotatedBounds(rect, rotation);

  final String id;

  /// The page id or canvas notebook id this element is on.
  final String surfaceId;

  /// The raw type name (see [ElementType]); unknown names are preserved.
  final String type;

  /// Unrotated box in world coordinates.
  final Rect rect;

  /// Clockwise rotation about [rect]'s centre, in radians.
  final double rotation;

  /// Stacking order among the surface's elements (higher is on top).
  /// Elements with a negative [z] are drawn beneath the ink ([belowInk]).
  final double z;

  /// Milliseconds since epoch.
  final int createdAt;

  /// Type-specific payload (e.g. text content and formatting).
  final Map<String, Object?> data;

  /// Axis-aligned world bounds of the rotated box.
  final Rect bounds;

  ElementType? get knownType => ElementType.parse(type);

  /// Whether the element is drawn beneath the ink (like a photo pasted
  /// into a notebook) rather than above it. Images start below the ink,
  /// text above; "bring to front" / "send to back" move between the two.
  bool get belowInk => z < 0;

  /// The rotated box's corners: top-left, top-right, bottom-right, bottom-left.
  List<Offset> get corners => rotatedCorners(rect, rotation);

  SurfaceElement copyWith({
    String? id,
    String? surfaceId,
    Rect? rect,
    double? rotation,
    double? z,
    int? createdAt,
    Map<String, Object?>? data,
  }) => SurfaceElement(
    id: id ?? this.id,
    surfaceId: surfaceId ?? this.surfaceId,
    type: type,
    rect: rect ?? this.rect,
    rotation: rotation ?? this.rotation,
    z: z ?? this.z,
    createdAt: createdAt ?? this.createdAt,
    data: data ?? this.data,
  );

  /// Whether world point [p] lies inside the rotated box.
  bool contains(Offset p) {
    final local = _rotate(p - rect.center, -rotation);
    return rect.contains(rect.center + local);
  }

  static List<Offset> rotatedCorners(Rect rect, double rotation) {
    final c = rect.center;
    return [
      for (final p in [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft])
        c + _rotate(p - c, rotation),
    ];
  }

  static Rect rotatedBounds(Rect rect, double rotation) {
    if (rotation == 0) return rect;
    final pts = rotatedCorners(rect, rotation);
    var r = Rect.fromPoints(pts[0], pts[1]);
    for (final p in pts.skip(2)) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r;
  }

  static Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle), s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// Stacking order: [z], then id for determinism across devices.
  static int paintOrder(SurfaceElement a, SurfaceElement b) {
    final byZ = a.z.compareTo(b.z);
    return byZ != 0 ? byZ : a.id.compareTo(b.id);
  }
}
