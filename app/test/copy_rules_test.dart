import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CONVENTIONS (copy): a single sentence shown on its own takes no full stop.
void main() {
  test('Text literals that are one sentence have no full stop', () {
    // Text('…') with a plain literal ending in "." (not "…"), and no second
    // sentence inside it.
    final literal = RegExp(r"""Text\(\s*'([^'$\\]*[^.])\.'\s*[,)]""");
    final twoSentences = RegExp(r'[.?!] [A-Z]');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final m in literal.allMatches(file.readAsStringSync())) {
        if (!twoSentences.hasMatch(m.group(1)!)) offenders.add('${file.path}: ${m.group(1)}.');
      }
    }
    expect(offenders, isEmpty);
  });
}
