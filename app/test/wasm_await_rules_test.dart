import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where [source] has `!await …` (or `!(await …)`) as the left operand of
/// `&&` / `||` whose right operand awaits too: one finding per place.
List<int> negatedAwaitBeforeAwait(String source) {
  final found = <int>[];
  for (final m in RegExp(r'!\s*\(?\s*await\b').allMatches(source)) {
    final line = source.substring(source.lastIndexOf('\n', m.start) + 1, m.start);
    if (line.trimLeft().startsWith('//')) continue; // Comments may name it.
    final ends = [source.indexOf(';', m.end), source.indexOf('{', m.end)].where((i) => i >= 0);
    final statement = source.substring(m.start, ends.isEmpty ? source.length : ends.reduce(_min));
    final op = RegExp(r'&&|\|\|').firstMatch(statement);
    if (op != null && RegExp(r'\bawait\b').hasMatch(statement.substring(op.end))) {
      found.add(m.start);
    }
  }
  return found;
}

int _min(int a, int b) => a < b ? a : b;

void main() {
  test('the rule finds the shape dart2wasm gets wrong, and only it', () {
    expect(negatedAwaitBeforeAwait('if (!await a() && !await b()) {'), hasLength(1));
    expect(negatedAwaitBeforeAwait('if (!(await a()) || await b()) {'), hasLength(1));
    expect(negatedAwaitBeforeAwait('if (!await a() && b()) {'), isEmpty);
    expect(negatedAwaitBeforeAwait('  // `!await a && await b`;'), isEmpty);
    expect(negatedAwaitBeforeAwait('final h = await a();\nif (!h && !await b()) {'), isEmpty);
  });

  // dart2wasm (Dart 3.13) compiles `!await a && await b` (and `||`) wrongly:
  // with `a` true it still took the branch, so web backups in WebAssembly
  // failed ("Blob … vanished while exporting") and recordings never played.
  // Await the left operand into a local first.
  test('no negated await before another await in a condition (dart2wasm)', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final at in negatedAwaitBeforeAwait(source)) {
        offenders.add('${file.path}:${'\n'.allMatches(source.substring(0, at)).length + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
