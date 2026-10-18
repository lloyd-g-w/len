/// A token of an RTF document ([tokenizeRtf]).
sealed class RtfToken {
  const RtfToken();
}

/// `{` ([open]) or `}`.
final class RtfGroup extends RtfToken {
  const RtfGroup({required this.open});

  final bool open;
}

/// A control word (`\b0`: name `b`, param 0) or control symbol (`\~`:
/// name `~`, no param; `\` before a line break is `par`).
final class RtfWord extends RtfToken {
  const RtfWord(this.name, [this.param]);

  final String name;
  final int? param;

  @override
  String toString() => '\\$name${param ?? ''}';
}

/// A `\'hh` byte, to decode by the current code page.
final class RtfByte extends RtfToken {
  const RtfByte(this.value);

  final int value;
}

/// Literal text (line breaks and NULs dropped, as RTF ignores them).
final class RtfText extends RtfToken {
  const RtfText(this.text);

  final String text;
}

bool _isLetter(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHex(int c) => _isDigit(c) || (c | 0x20) >= 0x61 && (c | 0x20) <= 0x66;

/// The tokens of [rtf], tolerantly: `\binN` data is skipped, a stray `\` at
/// the end is dropped, `\'` without two hex digits is ignored.
Iterable<RtfToken> tokenizeRtf(String rtf) sync* {
  final text = StringBuffer();
  var i = 0;
  final n = rtf.length;
  while (i < n) {
    final c = rtf.codeUnitAt(i);
    if (c != 0x5C && c != 0x7B && c != 0x7D) {
      if (c != 0x0A && c != 0x0D && c != 0) text.writeCharCode(c);
      i++;
      continue;
    }
    if (text.isNotEmpty) {
      yield RtfText(text.toString());
      text.clear();
    }
    i++;
    if (c != 0x5C) {
      yield RtfGroup(open: c == 0x7B);
      continue;
    }
    if (i >= n) break;
    final d = rtf.codeUnitAt(i);
    if (_isLetter(d)) {
      final start = i;
      while (i < n && _isLetter(rtf.codeUnitAt(i))) {
        i++;
      }
      final name = rtf.substring(start, i);
      final paramStart = i;
      if (i < n && rtf.codeUnitAt(i) == 0x2D) i++;
      final digits = i;
      while (i < n && _isDigit(rtf.codeUnitAt(i)) && i - digits < 10) {
        i++;
      }
      int? param;
      if (i > digits) {
        param = int.parse(rtf.substring(paramStart, i));
      } else {
        i = paramStart; // A lone `-` is text.
      }
      if (i < n && rtf.codeUnitAt(i) == 0x20) i++;
      if (name == 'bin' && param != null && param > 0) {
        i += param;
        continue;
      }
      yield RtfWord(name, param);
    } else if (d == 0x27) {
      final hex = i + 3 <= n && _isHex(rtf.codeUnitAt(i + 1)) && _isHex(rtf.codeUnitAt(i + 2))
          ? int.parse(rtf.substring(i + 1, i + 3), radix: 16)
          : null;
      i += hex == null ? 1 : 3;
      if (hex != null) yield RtfByte(hex);
    } else {
      i++;
      if (d == 0x5C || d == 0x7B || d == 0x7D) {
        text.writeCharCode(d);
      } else if (d == 0x0A || d == 0x0D) {
        yield const RtfWord('par');
      } else {
        yield RtfWord(String.fromCharCode(d));
      }
    }
  }
  if (text.isNotEmpty) yield RtfText(text.toString());
}
