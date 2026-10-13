import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The text of the string literal(s) at [i] in [source] — adjacent
/// literals (`'a' 'b'`, across lines) joined — or null unless the
/// argument is only literals (followed by `,` or `)`).
String? literalAt(String source, int i) {
  final text = StringBuffer();
  var any = false;
  while (true) {
    i = _skipSpace(source, i);
    if (i >= source.length) return null;
    var raw = false;
    if (source[i] == 'r' && i + 1 < source.length && "'\"".contains(source[i + 1])) {
      raw = true;
      i++;
    }
    final quote = source[i];
    if (quote != "'" && quote != '"') break;
    if (source.startsWith(quote * 3, i)) return null; // Multi-line strings: not UI copy.
    i++;
    while (i < source.length && source[i] != quote) {
      if (source[i] == '\n') return null;
      if (!raw && source[i] == r'\' && i + 1 < source.length) {
        text.write(source[i + 1]);
        i += 2;
        continue;
      }
      text.write(source[i]);
      i++;
    }
    i++; // The closing quote.
    any = true;
  }
  if (!any || (source[i] != ',' && source[i] != ')')) return null;
  return text.toString();
}

int _skipSpace(String source, int i) {
  while (i < source.length) {
    if (' \t\r\n'.contains(source[i])) {
      i++;
    } else if (source.startsWith('//', i)) {
      final eol = source.indexOf('\n', i);
      i = eol == -1 ? source.length : eol + 1;
    } else {
      break;
    }
  }
  return i;
}

/// Index just past the first top-level `,` from [i] (the end of an
/// argument), or -1.
int _afterArgument(String source, int i) {
  var depth = 0;
  for (; i < source.length; i++) {
    final c = source[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) {
      if (depth == 0) return -1;
      depth--;
    }
    if (c == ',' && depth == 0) return i + 1;
  }
  return -1;
}

/// The copy shown by `Text(…)` and as `showMessage(context, …)` in
/// [source], where it is written as string literals.
Iterable<String> uiCopy(String source) sync* {
  for (final m in RegExp(r'\b(Text|showMessage)\(').allMatches(source)) {
    var at = m.end;
    if (m.group(1) == 'showMessage') {
      at = _afterArgument(source, at);
      if (at == -1) continue;
    }
    if (literalAt(source, at) case final literal?) yield literal;
  }
}

/// Whether [copy] is a single sentence ending in a full stop (not "…" or
/// "...").
bool singleSentenceWithStop(String copy) =>
    copy.endsWith('.') && !copy.endsWith('..') && !RegExp(r'[.?!] [A-Z]').hasMatch(copy);

/// CONVENTIONS (copy): a single sentence shown on its own takes no full stop.
void main() {
  test('the scanner joins adjacent literals and reads messages', () {
    const source = '''
      Text('One line.'),
      Text(
        'Split over '
        "two lines.",
      ),
      Text('Two sentences. Fine.'),
      Text('Ellipsis…'),
      Text(name),
      Text('Interpolated \$name.', style: s),
      showMessage(context, 'Saved.');
      showMessage(anchor, 'Moved ' // why
        'to the end.', action: undo);
      showMessage(context, reason);
    ''';
    expect(uiCopy(source).where(singleSentenceWithStop), [
      'One line.',
      'Split over two lines.',
      r'Interpolated $name.',
      'Saved.',
      'Moved to the end.',
    ]);
  });

  test('UI copy that is one sentence has no full stop', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final copy in uiCopy(file.readAsStringSync())) {
        if (singleSentenceWithStop(copy)) offenders.add('${file.path}: $copy');
      }
    }
    expect(offenders, isEmpty);
  });
}
