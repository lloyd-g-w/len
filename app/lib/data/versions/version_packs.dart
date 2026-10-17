import 'dart:convert';
import 'dart:typed_data';

/// An item of a pack: a stroke's or element's id and its record `data`
/// (without `surfaceId`).
typedef PackItem = (String id, Map<String, Object?> data);

/// The packs of version history (docs/SYNC_PROTOCOL.md, "Version
/// history"): a surface's strokes, or its elements, in paint order, cut
/// into runs where an item's id says, so unchanged runs make the same
/// content-addressed blobs in every version.
abstract final class VersionPacks {
  /// The blob type of a pack.
  static const mime = 'application/x-len-pack';

  /// The pack format written and read.
  static const format = 1;

  /// A pack never holds more items than this.
  static const maxItems = 256;

  /// Cuts [items] (in paint order) into packs: after every item whose id
  /// hashes to a boundary (one in 32), and after [maxItems].
  static List<List<PackItem>> cut(List<PackItem> items) {
    final packs = <List<PackItem>>[];
    var run = <PackItem>[];
    for (final item in items) {
      run.add(item);
      if (run.length >= maxItems || isBoundary(item.$1)) {
        packs.add(run);
        run = [];
      }
    }
    if (run.isNotEmpty) packs.add(run);
    return packs;
  }

  /// Whether a pack ends after the item [id]: FNV-1a kept to 26 bits
  /// (products stay below 2^53, exact on the web too), mixed once more.
  static bool isBoundary(String id) {
    var h = 0x811c9dc5 & _mask;
    for (var i = 0; i < id.length; i++) {
      h = ((h ^ id.codeUnitAt(i)) * 0x01000193) & _mask;
    }
    h = ((h ^ (h >> 13)) * 0x5bd1e9) & _mask;
    return (h >> 10) & 31 == 0;
  }

  static const _mask = 0x3ffffff;

  /// The bytes of a pack of [items].
  static Uint8List encode(List<PackItem> items) => utf8.encode(
    jsonEncode({
      'v': format,
      'items': [
        for (final (id, data) in items) [id, data],
      ],
    }),
  );

  /// The items of pack [bytes]; null when they are no pack of [format].
  /// Items that are not an id and an object are left out.
  static List<PackItem>? decode(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (json case {'v': format, 'items': final List<Object?> items}) {
      return [
        for (final item in items)
          if (item case [final String id, final Map<String, Object?> data] when id.isNotEmpty)
            (id, data),
      ];
    }
    return null;
  }
}
