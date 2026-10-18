import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/text/text_font.dart';
import '../../domain/text/user_font.dart';

/// Which text-box fonts this app can show: the bundled ones always, a
/// user font while it is in the library ([setLibrary]) and has been
/// loaded into the engine ([load], through `FontLoader`, on every platform
/// the web included). Everything that lays out text boxes asks [familyOf],
/// so a font that is missing (not downloaded yet, broken or removed) falls
/// back to the default font instead of to a system font.
///
/// App-wide (the engine's fonts are): the app's `UserFontLibrary` keeps it
/// up to date. [changes] ticks whenever what is shown changes, so cached
/// layouts and pictures are rebuilt.
abstract final class TextFonts {
  static Map<String, UserFont> _library = const {};
  static final Set<String> _loaded = {};
  static final Map<String, Future<bool>> _loading = {};

  /// Ticks when a user font becomes available or stops being.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// The family to lay [font] out in: its own while [isShown], else the
  /// default font's.
  static String familyOf(TextFont font) => isShown(font) ? font.family : TextFont.inter.family;

  /// Whether text in [font] is drawn in it: a bundled font, or a user font
  /// in the library and loaded.
  static bool isShown(TextFont font) =>
      !font.isUser || (_library.containsKey(font.name) && _loaded.contains(font.name));

  /// The library's record of user font [font] (null: bundled, or removed /
  /// not synced here).
  static UserFont? userFont(TextFont font) => font.isUser ? _library[font.name] : null;

  /// The name to show for [font]: a bundled font's label, a user font's
  /// name, or "Missing font".
  static String labelOf(TextFont font) =>
      font.isUser ? (_library[font.name]?.name ?? 'Missing font') : font.label;

  /// The user fonts of the library, by name.
  static List<UserFont> get library => _library.values.toList();

  /// Sets the fonts in the library ([fonts] in picker order).
  static void setLibrary(List<UserFont> fonts) {
    final next = {for (final f in fonts) f.id: f};
    if (mapEquals(next, _library)) return;
    _library = next;
    changes.value++;
  }

  /// Whether text element data [data] uses a user font (its box's, or a
  /// span's): how it looks then depends on what is loaded, so pictures of
  /// it are not kept across launches.
  static bool usesUserFonts(Map<String, Object?> data) {
    if (TextFont.isUserId(data['font'])) return true;
    final spans = data['spans'];
    if (spans is! List) return false;
    for (final span in spans) {
      if (span case [_, _, final Map<Object?, Object?> style] when TextFont.isUserId(style['f'])) {
        return true;
      }
    }
    return false;
  }

  /// Whether font [id] has been loaded into the engine.
  static bool isLoaded(String id) => _loaded.contains(id);

  /// Loads the font file [bytes] as user font [id] (once; later calls
  /// return the first one's result). False if the engine refused it.
  static Future<bool> load(String id, Uint8List bytes) => _loading[id] ??= _load(id, bytes);

  static Future<bool> _load(String id, Uint8List bytes) async {
    try {
      await (FontLoader(
        TextFont.user(id).family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    } on Object catch (e) {
      debugPrint('Font $id could not be loaded: $e');
      return false;
    }
    _loaded.add(id);
    changes.value++;
    return true;
  }

  /// Forgets the library (tests; loaded fonts stay in the engine and are
  /// remembered as loaded).
  @visibleForTesting
  static void reset() {
    _library = const {};
    changes.value++;
  }
}
