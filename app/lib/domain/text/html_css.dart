import 'paragraph_style.dart';

/// The formatting one HTML element contributes, from its tag and its
/// inline `style` (which wins, e.g. Google Docs' wrapping
/// `<b style="font-weight:normal">`). Null / false = inherited.
class ElementFormat {
  const ElementFormat({
    required this.tag,
    this.bold,
    this.italic,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.pre = false,
    this.color,
    this.highlight,
    this.heading = 0,
    this.list,
    this.checked,
    this.listLevel,
    this.hidden = false,
  });

  final String tag;
  final bool? bold;
  final bool? italic;
  final bool underline;
  final bool strike;
  final bool mono;

  /// Whitespace is kept (`<pre>`, `white-space: pre`).
  final bool pre;
  final int? color;
  final int? highlight;

  /// Heading level of h1 – h3 (0 = none).
  final int heading;

  /// The kind of list a `<ul>` / `<ol>` holds.
  final ListKind? list;

  /// A checklist `<li>` (ARIA checkbox, Google Docs): whether it is ticked.
  final bool? checked;

  /// Explicit list nesting (0 = top): `aria-level` on an `<li>` (Google
  /// Docs) or Word's `mso-list: … level2` on a paragraph.
  final int? listLevel;

  /// Decoration for sighted readers only (`aria-hidden="true"`, such as
  /// the ☐ / ☑ Len writes before checklist items): its text is skipped.
  final bool hidden;

  factory ElementFormat.of(String tag, Map<String, String> attrs) {
    final css = parseCss(attrs['style'] ?? '');
    final weight = css['font-weight'];
    final fontStyle = css['font-style'];
    final decoration = '${css['text-decoration'] ?? ''} ${css['text-decoration-line'] ?? ''}';
    final family = css['font-family']?.toLowerCase() ?? '';
    final ariaLevel = int.tryParse(attrs['aria-level'] ?? '');
    final msoLevel = RegExp(r'level(\d+)').firstMatch(css['mso-list'] ?? '')?.group(1);
    final role = attrs['role'], ariaChecked = attrs['aria-checked'];
    final level = ariaLevel ?? (msoLevel == null ? null : int.parse(msoLevel));
    return ElementFormat(
      tag: tag,
      bold: weight != null
          ? _isBold(weight)
          : const {'b', 'strong', 'th', 'h4', 'h5', 'h6', 'dt'}.contains(tag)
          ? true
          : null,
      italic: fontStyle != null
          ? fontStyle.contains('italic') || fontStyle.contains('oblique')
          : const {'i', 'em', 'cite', 'var', 'dfn', 'address'}.contains(tag)
          ? true
          : null,
      underline: decoration.contains('underline') || tag == 'u' || tag == 'ins',
      strike: decoration.contains('line-through') || const {'s', 'strike', 'del'}.contains(tag),
      mono:
          const {'code', 'pre', 'tt', 'kbd', 'samp'}.contains(tag) ||
          family.contains('mono') ||
          family.contains('courier') ||
          family.contains('consolas'),
      pre: tag == 'pre' || (css['white-space']?.startsWith('pre') ?? false),
      color: parseColor(css['color'] ?? (tag == 'font' ? attrs['color'] : null)),
      highlight: tag == 'mark'
          ? 0xFFFFF176
          : parseColor(css['background-color'] ?? css['background']),
      heading: switch (tag) {
        'h1' => 1,
        'h2' || 'h3' => 2,
        _ => 0,
      },
      list: switch (tag) {
        'ul' || 'menu' => ListKind.bullet,
        'ol' => ListKind.number,
        _ => null,
      },
      checked: tag == 'li' && (role == 'checkbox' || ariaChecked != null)
          ? ariaChecked == 'true'
          : null,
      listLevel: level == null ? null : (level - 1).clamp(0, ParaStyle.maxIndent),
      hidden: attrs['aria-hidden']?.toLowerCase() == 'true',
    );
  }

  static bool _isBold(String weight) {
    final n = int.tryParse(weight);
    if (n != null) return n >= 600;
    return weight.startsWith('bold');
  }
}

/// The larger of the top and bottom margins an inline [css] style gives
/// a block, in multiples of its font size (`em` / `rem`; `px` and `pt`
/// taken against a 16 px / 12 pt body), or null where it sets none it
/// can read.
double? marginEm(Map<String, String> css) {
  double? length(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(-?[0-9]*\.?[0-9]+)([a-z%]*)$').firstMatch(v.trim());
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    if (n == 0) return 0;
    return switch (m.group(2)) {
      'em' || 'rem' => n,
      'px' => n / 16,
      'pt' => n / 12,
      _ => null,
    };
  }

  final parts = css['margin']?.split(RegExp(r'\s+')) ?? const <String>[];
  // The shorthand's top and bottom (one, two, three or four values).
  final top = length(css['margin-top']) ?? (parts.isEmpty ? null : length(parts[0]));
  final bottom =
      length(css['margin-bottom']) ??
      (parts.isEmpty ? null : length(parts.length >= 3 ? parts[2] : parts[0]));
  if (top == null && bottom == null) return null;
  final most = [?top, ?bottom].reduce((a, b) => a > b ? a : b);
  return most < 0 ? 0 : most;
}

/// Declarations of an inline `style` attribute (lower-case names; values
/// trimmed, `!important` dropped).
Map<String, String> parseCss(String style) {
  final out = <String, String>{};
  for (final decl in style.split(';')) {
    final colon = decl.indexOf(':');
    if (colon <= 0) continue;
    final name = decl.substring(0, colon).trim().toLowerCase();
    final value = decl.substring(colon + 1).replaceAll('!important', '').trim().toLowerCase();
    if (name.isNotEmpty && value.isNotEmpty) out[name] = value;
  }
  return out;
}

const _names = {
  'red': 0xFF0000,
  'green': 0x008000,
  'blue': 0x0000FF,
  'yellow': 0xFFFF00,
  'orange': 0xFFA500,
  'purple': 0x800080,
  'magenta': 0xFF00FF,
  'fuchsia': 0xFF00FF,
  'cyan': 0x00FFFF,
  'aqua': 0x00FFFF,
  'lime': 0x00FF00,
  'navy': 0x000080,
  'teal': 0x008080,
  'maroon': 0x800000,
  'olive': 0x808000,
};

/// An opaque ARGB colour from a CSS colour (`#rgb`, `#rrggbb`, `#rrggbbaa`,
/// `rgb()`, `rgba()`, basic names); null for none, transparent and greys —
/// black text on a white page or a page's own dark / light theme is not
/// formatting worth keeping in a box.
int? parseColor(String? css) {
  if (css == null) return null;
  final v = css.trim();
  int? rgb;
  if (v.startsWith('#')) {
    var hex = v.substring(1).split(RegExp(r'\s')).first;
    if (hex.length == 3 || hex.length == 4) {
      hex = [for (final c in hex.split('')) '$c$c'].join();
    }
    if (hex.length == 8) {
      if (hex.substring(6) == '00') return null;
      hex = hex.substring(0, 6);
    }
    if (hex.length == 6) rgb = int.tryParse(hex, radix: 16);
  } else if (RegExp(r'^rgba?\(').hasMatch(v)) {
    final close = v.lastIndexOf(')');
    final inner = v.substring(v.indexOf('(') + 1, close < 0 ? v.length : close);
    final parts = inner.split(RegExp(r'[,\s/]+'));
    final n = [for (final p in parts) num.tryParse(p.replaceAll('%', ''))];
    if (n.length < 3 || n.take(3).any((x) => x == null)) return null;
    if (n.length > 3 && n[3] != null && n[3] == 0) return null;
    int c(num x) => x.round().clamp(0, 255);
    rgb = c(n[0]!) * 0x10000 + c(n[1]!) * 0x100 + c(n[2]!);
  } else {
    rgb = _names[v.split(RegExp(r'\s')).first];
  }
  if (rgb == null || isGreyish(rgb)) return null;
  return 0xFF000000 + rgb; // (+, not |: web ints are 32-bit in bit operations)
}

/// Whether the colour [rgb] (alpha ignored) is a grey, black or white
/// (its channels spread less than 40): such colours are not formatting
/// (see [parseColor]).
bool isGreyish(int rgb) {
  final r = rgb >> 16 & 0xFF, g = rgb >> 8 & 0xFF, b = rgb & 0xFF;
  final spread =
      [r, g, b].reduce((a, b) => a > b ? a : b) - [r, g, b].reduce((a, b) => a < b ? a : b);
  return spread < 40;
}
