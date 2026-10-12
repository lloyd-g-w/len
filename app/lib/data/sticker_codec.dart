import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../domain/stickers/sticker.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'stroke_codec.dart';

/// The JSON form of [StickerContent] (a sticker's `content`, see
/// docs/SYNC_PROTOCOL.md): strokes in paint order with base64 float32
/// points, and elements with their box, stacking order and data.
abstract final class StickerCodec {
  static Map<String, Object?> encode(StickerContent content) {
    final strokes = [...content.strokes]..sort(Stroke.paintOrder);
    return {
      'strokes': [
        for (final s in strokes)
          {
            'tool': s.tool.name,
            'color': s.color,
            'width': s.width,
            'points': base64Encode(StrokeCodec.encode(s.points)),
            'style': s.style.toJson(),
          },
      ],
      'elements': [
        for (final e in content.elements)
          {
            'type': e.type,
            'x': e.rect.left,
            'y': e.rect.top,
            'w': e.rect.width,
            'h': e.rect.height,
            'rotation': e.rotation,
            'z': e.z,
            'data': e.data,
          },
      ],
    };
  }

  /// Parses [json] strictly; throws [FormatException] when malformed.
  static StickerContent decode(Object? json) {
    if (json is! Map<String, Object?>) throw const FormatException('content');
    final strokes = json['strokes'], elements = json['elements'];
    if (strokes is! List || elements is! List) throw const FormatException('content');
    T field<T>(Map<String, Object?> m, String key) {
      final v = m[key];
      if (v is T) return v;
      throw FormatException('content: $key');
    }

    double number(Map<String, Object?> m, String key) {
      final v = field<num>(m, key).toDouble();
      if (!v.isFinite) throw FormatException('content: $key');
      return v;
    }

    final decodedStrokes = <Stroke>[];
    for (final (i, raw) in strokes.indexed) {
      if (raw is! Map<String, Object?>) throw const FormatException('content: stroke');
      final tool = InkTool.parse(field<String>(raw, 'tool'));
      final Uint8List bytes;
      try {
        bytes = base64Decode(field<String>(raw, 'points'));
      } on FormatException {
        throw const FormatException('content: points');
      }
      final points = StrokeCodec.decode(bytes);
      if (points.isEmpty) throw const FormatException('content: points');
      decodedStrokes.add(
        Stroke(
          id: 's$i',
          surfaceId: '',
          tool: tool,
          color: field<int>(raw, 'color'),
          width: number(raw, 'width'),
          points: points,
          createdAt: i,
          style: StrokeStyle.fromJson(raw['style']),
        ),
      );
    }
    final decodedElements = <SurfaceElement>[];
    for (final (i, raw) in elements.indexed) {
      if (raw is! Map<String, Object?>) throw const FormatException('content: element');
      decodedElements.add(
        SurfaceElement(
          id: 'e$i',
          surfaceId: '',
          type: field<String>(raw, 'type'),
          rect: Rect.fromLTWH(
            number(raw, 'x'),
            number(raw, 'y'),
            number(raw, 'w'),
            number(raw, 'h'),
          ),
          rotation: number(raw, 'rotation'),
          z: number(raw, 'z'),
          createdAt: 0,
          data: field<Map<String, Object?>>(raw, 'data'),
        ),
      );
    }
    return StickerContent(strokes: decodedStrokes, elements: decodedElements);
  }
}
