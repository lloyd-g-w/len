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

/// Named arguments whose string is shown as it is: rows, captions,
/// tooltips, dialog messages.
const copyArguments = [
  'label',
  'title',
  'subtitle',
  'message',
  'tooltip',
  'caption',
  'hintText',
  'helperText',
  'labelText',
  'semanticLabel',
];

/// The copy shown by `Text(…)`, as `showMessage(context, …)` (or the
/// `_toast` / `showOverviewMessage` wrappers) and in [copyArguments] in
/// [source], where it is written as string literals.
Iterable<String> uiCopy(String source) sync* {
  final calls = RegExp(
    r'\b(Text|showMessage|_toast|showOverviewMessage)\(|'
    '\\b(?:${copyArguments.join('|')}): ',
  );
  for (final m in calls.allMatches(source)) {
    var at = m.end;
    if (m.group(1) case final call? when call != 'Text') {
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

/// Words that keep their capital inside a sentence: names, keys and the
/// sections and places Len names.
const properWords = {
  'Len', 'Android', 'Wi-Fi', 'S', 'Pen', 'Ink', 'Lab', 'My', 'Settings', 'Trash', //
  'Favourites', 'Library', 'Writing', 'Handwriting', 'Sync', 'General', 'Backup', //
  'Storage', 'About', 'Ctrl', 'Shift', 'Alt', 'Esc', 'Tab', 'Space', 'Home', 'End', //
  'Del', 'Menu', 'Type', 'Sofia', 'Sans', 'Inter', 'Lora', 'JetBrains', 'Mono', //
  'Caveat', 'Undo', 'Redo', 'Export…', 'Done', 'Keep', 'Set', 'Back', 'Locate', //
  'Turn', 'Try', 'Google', 'Chrome', 'Firefox', 'Safari', 'Linux', 'Windows', //
  'GoodNotes', 'Notewise', 'FlateDecode', 'Corrupt', 'Server', 'Enter', 'TrueType', //
  'OpenType',
};

/// Whether [copy] reads as Title Case: a word after the first starts with
/// a capital and isn't a name ([properWords]), an acronym or a sentence's
/// first word.
bool titleCased(String copy) {
  final words = copy.split(RegExp(r'\s+'));
  for (var i = 1; i < words.length; i++) {
    final word = words[i]
        .replaceAll(RegExp(r'^[(“‘"]+|’s$|[)”’",:;.!?]+$'), '')
        .replaceAll(RegExp(r'\+.*'), ''); // Ctrl+Z, Shift+Enter: keys.
    if (!RegExp(r'^[A-Z][a-z]').hasMatch(word)) continue; // Lower case, acronyms, 1 – 5.
    if (properWords.contains(word)) continue;
    if (RegExp(r'[.?!:;—]$').hasMatch(words[i - 1])) continue; // A new sentence.
    if (words[i - 1].contains(r'$') || word.contains(r'$')) continue;
    return true;
  }
  return false;
}

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
      _toast(context, 'Can’t do that.');
    ''';
    expect(uiCopy(source).where(singleSentenceWithStop), [
      'One line.',
      'Split over two lines.',
      r'Interpolated $name.',
      'Saved.',
      'Moved to the end.',
      'Can’t do that.',
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

  test('Title Case is told from names, keys and new sentences', () {
    expect(titleCased('Move To Trash'), isTrue);
    expect(titleCased('Export PDF Pages…'), isTrue);
    expect(titleCased('Import Len file…'), isFalse);
    expect(titleCased('Undo (Ctrl+Z)'), isFalse);
    expect(titleCased('Saved. Open the folder'), isFalse);
    expect(titleCased('Export as PDF'), isFalse);
  });

  // UX_AUDIT R24: rows, buttons and titles are sentence case; a capital
  // after the first word is a name (Len, PDF, Android, a key, a section).
  test('UI copy is sentence case', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final copy in uiCopy(file.readAsStringSync())) {
        if (titleCased(copy)) offenders.add('${file.path}: $copy');
      }
    }
    expect(offenders, isEmpty);
  });

  // CONVENTIONS (icons, colour): Material Symbols Rounded only; features pick
  // colours from the tokens (`Tones`, `Palette`, `Surfaces`, the scheme).
  test('no Material Icons, and no colour literals in features', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final feature = file.path.startsWith('lib/features/');
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (RegExp(r'\bIcons\.').hasMatch(line) ||
            (feature && RegExp(r'\bColor\(0x|\bColors\.(?!transparent\b)').hasMatch(line))) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  // UX_AUDIT R10-22: one apostrophe, the typographic one.
  test('UI strings use ’, not a straight apostrophe', () {
    final straight = RegExp(r"[A-Za-z]\\'[A-Za-z]");
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        final code = line.trimLeft();
        if (code.startsWith('//') || code.contains('debugPrint(')) continue;
        if (straight.hasMatch(line)) offenders.add('${file.path}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  // UX_AUDIT R9 glossary: one name per thing, in every string the app shows.
  test('UI strings use the glossary', () {
    const banned = {
      r'\bCould not\b': 'Couldn’t',
      r'\bRetry\b': 'Try again',
      r'\bthe Trash\b': 'the trash (Trash is only the section’s name)',
      r'\bkeeps at least one page\b': 'needs at least one page',
      r'^Star \w': 'Add to favourites',
      r'^(Whole page|Page width|Fit the content|Back to the start)$': 'the menus’ zoom names',
      r'^(Template…|Page templates|Edit folder…)$': 'Change template…, Templates, Rename…',
    };
    final literal = RegExp(
      r"'([^'\n]*)'|"
      r'"([^"\n]*)"',
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        final code = line.trimLeft();
        if (code.startsWith('//') || code.contains('debugPrint(')) continue;
        for (final m in literal.allMatches(line)) {
          final text = m.group(1) ?? m.group(2)!;
          for (final MapEntry(key: pattern, value: use) in banned.entries) {
            if (RegExp(pattern).hasMatch(text)) offenders.add('${file.path}: "$text" (use $use)');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
