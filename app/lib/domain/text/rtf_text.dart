import 'html_css.dart' show isGreyish;
import 'rtf_code_pages.dart';
import 'rtf_lines.dart';
import 'rtf_state.dart';
import 'rtf_tables.dart';
import 'rtf_tokens.dart';
import 'text_data.dart';

/// Formatted text from RTF on the clipboard, for apps that offer no HTML
/// (WordPad, TextEdit, LibreOffice and Word offer both): bold, italic,
/// underline, strikethrough, colours and highlights that are not grey,
/// monospaced fonts, font sizes relative to the body text's, headings
/// (`\outlinelevel` or heading styles), bulleted / numbered lists (Word's
/// list table, WordPad's `\pn`), one line per paragraph, the paragraph
/// spacing nearest the body paragraphs' `\sa` / `\sb` (else the [box]'s).
/// The font, size and colour are the [box]'s. Returns null when there is
/// no text (or [rtf] is not RTF).
TextData? textFromRtf(String rtf, TextData box) {
  var s = rtf.startsWith('\uFEFF') ? rtf.substring(1) : rtf;
  s = s.replaceFirst(RegExp(r'\x00+$'), '').trimLeft();
  if (!s.startsWith(r'{\rtf')) return null;
  final reader = _RtfReader(box.font == TextFont.mono);
  for (final token in tokenizeRtf(s)) {
    reader.add(token);
  }
  return reader.lines.result(box);
}

/// Unstarred destinations whose content is not text.
const _hidden = {
  'info', 'pict', 'object', 'objdata', 'header', 'headerl', 'headerr', 'headerf', 'footer', //
  'footerl', 'footerr', 'footerf', 'footnote', 'fldinst', 'filetbl', 'revtbl', 'rsidtbl', 'author',
  'operator', 'title', 'subject', 'keywords', 'comment', 'doccomm', 'company', 'creatim', 'revtim',
  'printim', 'buptim', 'nonshppict', 'xe', 'tc', 'txe', 'rxe', 'annotation', 'atnid', 'atnauthor',
  'bkmkstart', 'bkmkend', 'themedata', 'colorschememapping', 'datastore', 'latentstyles',
  'generator', 'xmlnstbl', 'mmathPr', 'pgdsctbl', 'listpicture', 'userprops', 'template',
  'expandedcolortbl', 'docvar', 'protusertbl', 'ftnsep', 'ftnsepc', 'ftncn', 'aftnsep',
  'aftnsepc', 'aftncn', 'shpinst', 'sp', 'formfield', 'datafield', 'hl', 'passwordhash',
  'defchp', 'defpap', 'fchars', 'lchars', 'wgrffmtfilter',
};

/// Control words (and symbols) that stand for characters.
const _chars = {
  'tab': '\t', '~': ' ', '_': '-', '-': '', 'emdash': '\u2014', 'endash': '\u2013', //
  'bullet': '\u2022', 'lquote': '\u2018', 'rquote': '\u2019', 'ldblquote': '\u201C',
  'rdblquote': '\u201D', 'emspace': ' ', 'enspace': ' ', 'qmspace': ' ',
};

class _RtfReader {
  _RtfReader(this.monoBox);

  final bool monoBox;
  final tables = RtfTables();
  final lines = RtfLines();
  final _stack = <RtfState>[];
  RtfState _state = RtfState();

  /// Fallback characters of a `\u` still to skip.
  int _skip = 0;

  /// The last word was `\*`.
  bool _starred = false;

  void add(RtfToken token) {
    switch (token) {
      case RtfGroup(open: true):
        _skip = 0;
        _starred = false;
        _stack.add(_state);
        _state = _state.copy();
        tables.groupStart(_state.dest);
      case RtfGroup():
        _skip = 0;
        _starred = false;
        if (_stack.isEmpty) return;
        final inner = _state;
        _state = _stack.removeLast();
        if (inner.dest == RtfDest.pn && _state.dest != RtfDest.pn) {
          _state.pn = inner.pnNumber && !inner.pnBullet ? ListKind.number : ListKind.bullet;
          _state.pnLevel = inner.pnLevel;
        }
      case RtfWord(:final name, :final param):
        _word(name, param);
      case RtfByte(:final value):
        if (_skip > 0) {
          _skip--;
        } else {
          _text(decodeCodePageByte(value, _codePage));
        }
      case RtfText(:final text):
        final skip = _skip.clamp(0, text.length);
        _skip -= skip;
        _text(skip == 0 ? text : text.substring(skip));
    }
  }

  int get _codePage => tables.fonts[_state.font]?.codePage ?? tables.codePage;

  void _word(String name, int? param) {
    _skip = 0;
    if (name == '*') {
      _starred = true;
      return;
    }
    final starred = _starred;
    _starred = false;
    if (_state.dest == RtfDest.skip) return;
    if (_destination(name, starred) case final dest?) {
      _state.dest = dest;
      if (dest == RtfDest.pn) _state.pnBullet = _state.pnNumber = false;
      if (dest == RtfDest.marker) lines.startMarker();
      tables.groupStart(dest);
      return;
    }
    switch (_state.dest) {
      case RtfDest.text || RtfDest.marker || RtfDest.pn:
        _textWord(name, param);
      case RtfDest.skip:
        break;
      case final dest:
        tables.word(dest, name, param);
    }
  }

  /// The destination [name] starts, or null if it is none.
  RtfDest? _destination(String name, bool starred) {
    final dest = switch (name) {
      'fonttbl' => RtfDest.fonts,
      'colortbl' => RtfDest.colors,
      'stylesheet' => RtfDest.styles,
      'listtable' => RtfDest.lists,
      'listoverridetable' => RtfDest.overrides,
      'listtext' || 'pntext' => RtfDest.marker,
      'pn' => RtfDest.pn,
      'fldrslt' => _state.dest,
      _ when _hidden.contains(name) => RtfDest.skip,
      _ => null,
    };
    return dest ?? (starred ? RtfDest.skip : null);
  }

  void _textWord(String name, int? param) {
    if (_state.apply(name, param, tables)) return;
    if (_chars[name] case final c?) return _text(c);
    switch (name) {
      case 'par' || 'line' || 'sect' || 'page' || 'row' || 'nestrow':
        if (_state.dest == RtfDest.text) lines.newLine(_para());
      case 'cell' || 'nestcell':
        if (!lines.current.isEmpty) _text(' ');
      case 'u':
        final v = param ?? 0;
        _text(String.fromCharCode(v < 0 ? v + 65536 : v & 0xFFFF));
        _skip = _state.uc;
      case 'ansicpg':
        tables.codePage = param ?? 1252;
      case 'mac':
        tables.codePage = 10000;
      case 'pc':
        tables.codePage = 437;
      case 'pca':
        tables.codePage = 850;
      case 'deff':
        tables.defaultFont = param ?? 0;
        if (_state.font < 0) _state.font = tables.defaultFont;
    }
  }

  void _text(String text) {
    if (text.isEmpty) return;
    switch (_state.dest) {
      case RtfDest.marker:
        lines.marker(text);
      case RtfDest.text:
        if (!_state.hidden) lines.add(text, _style(), _state.half, _para);
      case RtfDest.skip || RtfDest.pn:
        break;
      case final dest:
        tables.text(dest, text);
    }
  }

  SpanStyle _style() {
    final s = _state;
    final font = tables.fonts[s.font];
    return SpanStyle(
      bold: s.bold || (font?.bold ?? false),
      italic: s.italic || (font?.italic ?? false),
      underline: s.underline,
      strike: s.strike,
      color: _color(s.color),
      highlight: _color(s.highlight),
      font: (font?.mono ?? false) && !monoBox ? TextFont.mono : null,
    );
  }

  /// The colour at [index] of the colour table, unless auto or a grey.
  int? _color(int index) {
    final colors = tables.colors;
    final argb = index >= 0 && index < colors.length ? colors[index] : null;
    return argb == null || isGreyish(argb) ? null : argb;
  }

  /// The current paragraph's formatting.
  RtfPara _para() {
    final s = _state;
    final heading = switch (s.outline) {
      0 => 1,
      1 || 2 => 2,
      _ => tables.styleHeadings[s.style] ?? 0,
    };
    final spaces = [?s.spaceAfter, ?s.spaceBefore];
    return RtfPara(
      heading: heading,
      listed: s.ls > 0 || s.pn != null,
      tableKind: s.ls > 0 ? tables.listKind(s.ls, s.ilvl) : null,
      pn: s.pn,
      indent: (s.ls > 0 ? s.ilvl : s.pnLevel).clamp(0, ParaStyle.maxIndent),
      space: spaces.isEmpty ? null : spaces.reduce((a, b) => a > b ? a : b),
    );
  }
}
