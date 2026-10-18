import 'paragraph_style.dart';
import 'rtf_tables.dart';

/// The state an RTF group saves and restores: its destination, character
/// and paragraph formatting.
class RtfState {
  RtfState();

  RtfDest dest = RtfDest.text;

  /// `\uc`: how many fallback characters follow a `\u`.
  int uc = 1;

  // Character formatting (`\plain` resets it).
  bool bold = false, italic = false, underline = false, strike = false, hidden = false;
  int font = -1;

  /// `\fs`: size in half points.
  int half = 24;

  /// Colour table indices (0 = auto).
  int color = 0, highlight = 0;

  // Paragraph formatting (`\pard` resets it).
  /// `\outlinelevel` (-1: none).
  int outline = -1;

  /// `\s`: the paragraph style.
  int style = 0;

  /// `\ls` (0: not a list item) and `\ilvl` (0-based).
  int ls = 0, ilvl = 0;

  /// `\sa` / `\sb` in twips, null where not set.
  int? spaceAfter, spaceBefore;

  /// The list kind `\pn` numbering gives (null: none), its level (0-based).
  ListKind? pn;
  int pnLevel = 0;

  /// Inside a `\pn` group: bullets (`\pnlvlblt`) or a numbering style.
  bool pnBullet = false, pnNumber = false;

  RtfState copy() => RtfState()
    ..dest = dest
    ..uc = uc
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..strike = strike
    ..hidden = hidden
    ..font = font
    ..half = half
    ..color = color
    ..highlight = highlight
    ..outline = outline
    ..style = style
    ..ls = ls
    ..ilvl = ilvl
    ..spaceAfter = spaceAfter
    ..spaceBefore = spaceBefore
    ..pn = pn
    ..pnLevel = pnLevel
    ..pnBullet = pnBullet
    ..pnNumber = pnNumber;

  /// `\plain`.
  void resetCharacter(int defaultFont) {
    bold = italic = underline = strike = hidden = false;
    font = defaultFont;
    half = 24;
    color = highlight = 0;
  }

  /// `\pard`.
  void resetParagraph() {
    outline = -1;
    style = ls = ilvl = pnLevel = 0;
    spaceAfter = spaceBefore = null;
    pn = null;
  }

  /// Applies a formatting control word; false if [name] isn't one.
  bool apply(String name, int? param, RtfTables tables) {
    final on = param != 0;
    switch (name) {
      case 'plain':
        resetCharacter(tables.defaultFont);
      case 'pard':
        resetParagraph();
      case 'b':
        bold = on;
      case 'i':
        italic = on;
      case 'strike' || 'striked':
        strike = on;
      case 'v' || 'webhidden':
        hidden = on;
      case 'ulnone':
        underline = false;
      case 'ul' || 'uld' || 'uldash' || 'uldashd' || 'uldashdd' || 'uldb' || 'ulhwave':
      case 'ulldash' || 'ulth' || 'ulthd' || 'ulthdash' || 'ulthdashd' || 'ulthdashdd':
      case 'ulthldash' || 'ululdbwave' || 'ulw' || 'ulwave':
        underline = on;
      case 'f':
        font = param ?? 0;
      case 'fs':
        if (param != null && param > 0) half = param;
      case 'cf':
        color = param ?? 0;
      case 'highlight' || 'cb' || 'chcbpat':
        highlight = param ?? 0;
      case 'uc':
        uc = (param ?? 1).clamp(0, 10);
      case 'outlinelevel':
        outline = param ?? -1;
      case 's':
        style = param ?? 0;
      case 'ls':
        ls = param ?? 0;
      case 'ilvl':
        ilvl = param ?? 0;
      case 'sa':
        spaceAfter = param;
      case 'sb':
        spaceBefore = param;
      default:
        return _applyPn(name, param);
    }
    return true;
  }

  bool _applyPn(String name, int? param) {
    switch (name) {
      case 'pnlvlblt':
        pnBullet = true;
      case 'pnlvlbody':
        pnLevel = 0;
      case 'pnlvl':
        pnLevel = ((param ?? 1) - 1).clamp(0, ParaStyle.maxIndent);
      case 'pndec' || 'pnucltr' || 'pnlcltr' || 'pnucrm' || 'pnlcrm' || 'pnord' || 'pncard':
        pnNumber = true;
      default:
        return false;
    }
    return true;
  }
}
