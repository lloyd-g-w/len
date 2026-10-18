import 'paragraph_style.dart';
import 'rtf_code_pages.dart';

/// Where the text and control words of an RTF group go.
enum RtfDest {
  /// The document's text (also a field's `\fldrslt`).
  text,

  /// Ignored: pictures, objects, headers, document info, unknown `\*`
  /// destinations.
  skip,

  /// `\fonttbl`.
  fonts,

  /// `\colortbl`.
  colors,

  /// `\stylesheet`.
  styles,

  /// `\listtable`.
  lists,

  /// `\listoverridetable`.
  overrides,

  /// A list item's marker (`\listtext`, `\pntext`): not text, but tells
  /// a bullet from a number.
  marker,

  /// Word 95 / WordPad paragraph numbering (`\pn`).
  pn,
}

/// A font of the font table.
class RtfFont {
  String name = '';

  /// From `\fcharset`; null = the document's.
  int? codePage;

  /// `\fmodern` (fixed pitch families) or `\fprq1` (fixed pitch).
  bool fixed = false;

  /// A monospaced font (code).
  bool get mono {
    final n = name.toLowerCase();
    return fixed || _monoNames.any(n.contains);
  }

  /// A bold face named as a font of its own (Cocoa: `Helvetica-Bold`).
  bool get bold => name.toLowerCase().contains('bold');

  /// An italic face named as a font of its own (`Helvetica-Oblique`).
  bool get italic {
    final n = name.toLowerCase();
    return n.contains('italic') || n.contains('oblique');
  }

  static const _monoNames = [
    'courier', 'consolas', 'menlo', 'monaco', 'mono', 'lucida console', 'andale', //
    'inconsolata', 'source code', 'fira code', 'fixedsys', 'cascadia code',
  ];
}

/// The tables in an RTF document's header: fonts, colours, heading
/// styles and list formats, filled from the words and text of their
/// destinations.
class RtfTables {
  /// The document's code page (`\ansicpg`; `\mac`, `\pc`, `\pca`).
  int codePage = 1252;

  /// `\deff`: the font `\plain` resets to.
  int defaultFont = -1;

  final fonts = <int, RtfFont>{};

  /// ARGB colours by index (null: auto, the box's).
  final colors = <int?>[];

  /// Heading level (1, 2) of paragraph styles by `\s` number.
  final styleHeadings = <int, int>{};

  /// `\levelnfc` of each level of each list, by `\listid`.
  final _lists = <int, List<int>>{};

  /// `\listid` by `\ls` (the override table).
  final _overrides = <int, int>{};

  final _name = StringBuffer();
  RtfFont? _font;
  int? _r, _g, _b;
  int? _style;
  int? _styleOutline;
  List<int> _levels = [];
  int? _overrideList;

  /// A group starts in [dest].
  void groupStart(RtfDest dest) {
    if (dest == RtfDest.styles) {
      _style = null;
      _styleOutline = null;
      _name.clear();
    }
  }

  /// A control word in [dest].
  void word(RtfDest dest, String name, int? param) {
    switch ((dest, name)) {
      case (RtfDest.fonts, 'f'):
        _font = fonts.putIfAbsent(param ?? 0, RtfFont.new);
        _name.clear();
      case (RtfDest.fonts, 'fmodern'):
        _font?.fixed = true;
      case (RtfDest.fonts, 'fprq'):
        if (param == 1) _font?.fixed = true;
      case (RtfDest.fonts, 'fcharset'):
        _font?.codePage = codePageOfCharset(param ?? 0);
      case (RtfDest.colors, 'red'):
        _r = (param ?? 0).clamp(0, 255);
      case (RtfDest.colors, 'green'):
        _g = (param ?? 0).clamp(0, 255);
      case (RtfDest.colors, 'blue'):
        _b = (param ?? 0).clamp(0, 255);
      case (RtfDest.styles, 's'):
        _style = param ?? 0;
      case (RtfDest.styles, 'outlinelevel'):
        _styleOutline = param;
      case (RtfDest.lists, 'list'):
        _levels = [];
      case (RtfDest.lists, 'listlevel'):
        _levels.add(0);
      case (RtfDest.lists, 'levelnfc' || 'levelnfcn'):
        if (_levels.isNotEmpty) _levels[_levels.length - 1] = param ?? 0;
      case (RtfDest.lists, 'listid'):
        if (param != null) _lists[param] = _levels;
      case (RtfDest.overrides, 'listoverride'):
        _overrideList = null;
      case (RtfDest.overrides, 'listid'):
        _overrideList = param;
      case (RtfDest.overrides, 'ls'):
        if (param != null && _overrideList != null) _overrides[param] = _overrideList!;
    }
  }

  /// Literal text in [dest]: names up to `;` (fonts, styles), `;` ending
  /// a colour.
  void text(RtfDest dest, String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c != ';') {
        if (dest == RtfDest.fonts || dest == RtfDest.styles) _name.write(c);
        continue;
      }
      switch (dest) {
        case RtfDest.fonts:
          _font?.name = _name.toString().trim();
          _name.clear();
        case RtfDest.colors:
          final set = _r != null || _g != null || _b != null;
          final rgb = (_r ?? 0) * 0x10000 + (_g ?? 0) * 0x100 + (_b ?? 0);
          colors.add(set ? 0xFF000000 + rgb : null);
          _r = _g = _b = null;
        case RtfDest.styles:
          final name = _name.toString().trim().toLowerCase();
          final heading = switch (_styleOutline) {
            0 => 1,
            1 || 2 => 2,
            _ =>
              name == 'heading 1'
                  ? 1
                  : name == 'heading 2' || name == 'heading 3'
                  ? 2
                  : 0,
          };
          if (heading > 0) styleHeadings[_style ?? 0] = heading;
          _name.clear();
        default:
      }
    }
  }

  /// The kind of list `\ls` [ls] makes at level [ilvl] from the list
  /// table (`\levelnfc` 23 is a bullet, 255 no marker: [ListKind.none]);
  /// null where the table doesn't tell.
  ListKind? listKind(int ls, int ilvl) {
    final levels = _lists[_overrides[ls] ?? -1];
    if (levels == null || levels.isEmpty) return null;
    return switch (levels[ilvl.clamp(0, levels.length - 1)]) {
      23 => ListKind.bullet,
      255 => ListKind.none,
      _ => ListKind.number,
    };
  }
}
