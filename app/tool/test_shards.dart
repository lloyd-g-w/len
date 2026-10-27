// Bundles the test files into a few shard files for tool/test.sh:
//   dart run tool/test_shards.dart generate <slow|fast|all> <shards> <out dir>
//   dart run tool/test_shards.dart record <json report> [<json report> ...]
//
// `flutter test` compiles every test file on its own, one after another in a
// single compiler, and writes a whole-app kernel for each: with ~450 files
// that serial compile (and ~60 GB of disk writes) is most of a run, not the
// tests. A shard imports many test files and runs each one's `main` in a
// group named after the file, so a run compiles a few dozen programs.
//
// Each file keeps what package:test would give it alone: its library `@Tags`
// (shards hold files of one tag set and carry it) and goldens resolved next
// to it (`goldenFileComparator`), and starts with no planner labels cached
// (`PatternText`: they keep the font they were laid out in). Files that load Roboto into the engine
// (for good: [loadsFonts]) get shards of their own, so the others' goldens
// keep the test font.
// Files are spread over the shards by their recorded time
// (tool/test_times.json, refreshed by `record`; `tool/test.sh --record`),
// longest first, and the shards are listed longest first, so the long files
// start at once and the shards end together.
import 'dart:convert';
import 'dart:io';

const _timesPath = 'tool/test_times.json';

/// Seconds assumed for a file with no recorded time.
const _unknownSeconds = 2.0;

void main(List<String> args) {
  if (args.length == 1 && args[0] == 'fonts') {
    stdout.writeln(_fontHelpers.join(' '));
    for (final f in testFiles('all').where(loadsFonts)) {
      stdout.writeln(f);
    }
    return;
  }
  if (args.length == 4 && args[0] == 'generate') {
    generate(args[1], int.parse(args[2]), Directory(args[3]));
  } else if (args.length >= 2 && args[0] == 'record') {
    record(args.skip(1).toList());
  } else {
    stderr.writeln(
      'usage: test_shards.dart generate <slow|fast|all> <shards> <out dir>\n'
      '       test_shards.dart record <json report>...',
    );
    exit(64);
  }
}

/// The test files (relative to test/, `/`-separated) of [tier]: the fast
/// tier leaves out test/perf/ and test/screenshots/ (slow as a whole).
List<String> testFiles(String tier) {
  final root = Directory('test');
  final files = [
    for (final f in root.listSync(recursive: true))
      if (f is File && f.path.endsWith('_test.dart'))
        f.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
  ]..sort();
  if (tier == 'all') return files;
  return [
    for (final f in files)
      if (isSlow(f) == (tier == 'slow')) f,
  ];
}

/// Whether the test file at [path] is in the slow tier: tagged `slow`, or
/// with a tag dart_test.yaml adds `slow` to (`perf`, `screenshots`).
bool isSlow(String path) => libraryTags(path).any(_slowTags.contains);

final Set<String> _slowTags = () {
  final tags = {'slow'};
  String? tag;
  for (final line in File('dart_test.yaml').readAsLinesSync()) {
    if (RegExp(r'^  (\w+):').firstMatch(line) case final m?) tag = m[1];
    if (tag != null && RegExp(r'^\s+add_tags:.*\bslow\b').hasMatch(line)) tags.add(tag);
  }
  return tags;
}();

/// The library `@Tags([...])` of the test file at [path].
List<String> libraryTags(String path) {
  final source = File('test/$path').readAsStringSync();
  final match = RegExp(r'^@Tags\(\[([^\]]*)\]\)', multiLine: true).firstMatch(source);
  if (match == null) return const [];
  return [
    for (final t in match[1]!.split(','))
      if (t.trim().isNotEmpty) t.trim().replaceAll(RegExp('''['"]'''), ''),
  ];
}

/// Writes `shard_NN.dart` files to [out] (emptied first) and prints their
/// paths and those of the files that run alone ([runsAlone]), longest
/// first. A shard holds files of one set of library tags (flutter_test's
/// `group` takes no tags, so the shard carries them as its own `@Tags`) that
/// all load fonts or all don't ([loadsFonts]); each such set gets shards in
/// proportion to its time.
void generate(String tier, int shardCount, Directory out) {
  final times = _readTimes();
  double time(String f) => times[f] ?? _unknownSeconds;
  final byTags = <String, List<String>>{};
  final alone = <String>[];
  for (final f in testFiles(tier)) {
    if (runsAlone(f)) {
      alone.add(f);
    } else {
      (byTags['${libraryTags(f).join(',')}|${loadsFonts(f)}'] ??= []).add(f);
    }
  }
  final total = byTags.values.expand((fs) => fs).fold(0.0, (t, f) => t + time(f));
  final shards = <(List<String>, List<String>, double)>[];
  for (final MapEntry(:key, value: files) in byTags.entries) {
    final tags = key.split('|').first;
    files.sort((a, b) => time(b).compareTo(time(a)));
    final share = files.fold(0.0, (t, f) => t + time(f)) / total;
    final count = (shardCount * share).round().clamp(1, files.length);
    final groups = List.generate(count, (_) => <String>[]);
    final load = List.filled(count, 0.0);
    for (final f in files) {
      var least = 0;
      for (var i = 1; i < count; i++) {
        if (load[i] < load[least]) least = i;
      }
      groups[least].add(f);
      load[least] += time(f);
    }
    for (var i = 0; i < count; i++) {
      shards.add((tags.isEmpty ? const [] : tags.split(','), groups[i]..sort(), load[i]));
    }
  }
  shards.sort((a, b) => b.$3.compareTo(a.$3));
  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);
  final testDir = Directory('test').absolute.uri;
  final toTest = _relativeUp(out);
  final paths = <(String, double)>[for (final f in alone) ('test/$f', time(f))];
  for (final (n, (tags, files, load)) in shards.indexed) {
    final path = '${out.path}/shard_${n.toString().padLeft(2, '0')}.dart';
    File(path).writeAsStringSync(_shardSource(files, tags, testDir, toTest));
    paths.add((path, load));
  }
  paths.sort((a, b) => b.$2.compareTo(a.$2));
  for (final (path, _) in paths) {
    stdout.writeln(path);
  }
}

/// Whether the test file at [path] loads fonts into the engine beyond
/// those every file gets (`flutter_test_config.dart`): Roboto, through
/// `loadFonts` in content_golden_test.dart, a helper that uses it
/// ([_fontHelpers]) or a `FontLoader` of its own. Nothing unloads them, so in
/// a shard with them, later files' goldens would show Roboto where they were
/// made with the test font.
bool loadsFonts(String path) => _callsFontLoading(File('test/$path').readAsStringSync());

bool _callsFontLoading(String source) =>
    source.contains('FontLoader(') ||
    _fontHelpers.any((name) => RegExp('\\b$name\\b').hasMatch(source));

/// The public top-level functions in test/ that load fonts, directly or
/// through another such function (`loadFonts`, `seededCanvas`, ...).
final Set<String> _fontHelpers = () {
  final names = {'loadFonts'};
  final declarations = <String, String>{}; // public name → its source
  for (final f in Directory('test').listSync(recursive: true).whereType<File>()) {
    // flutter_test_config.dart's fonts are every file's.
    if (!f.path.endsWith('.dart') || f.path.contains('/.shards/')) continue;
    if (f.path.endsWith('flutter_test_config.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^[A-Za-z][\w<>?, ()]*?\b([a-z]\w*)\(').firstMatch(lines[i]);
      if (m == null || const {'void', 'main', 'if', 'for'}.contains(m[1])) continue;
      final body = StringBuffer(lines[i]);
      for (var j = i + 1; j < lines.length && !RegExp(r'^\S').hasMatch(lines[j]); j++) {
        body.writeln(lines[j]);
      }
      declarations[m[1]!] = '${declarations[m[1]!] ?? ''}$body';
    }
  }
  for (var grew = true; grew;) {
    grew = false;
    for (final MapEntry(key: name, value: body) in declarations.entries) {
      if (names.contains(name)) continue;
      if (body.contains('FontLoader(') || names.any((n) => RegExp('\\b$n\\b').hasMatch(body))) {
        names.add(name);
        grew = true;
      }
    }
  }
  return names;
}();

/// Whether the test file at [path] must run in an isolate of its own, as
/// a `// test_shards: alone` comment in it says (state it cannot reset).
bool runsAlone(String path) =>
    File('test/$path').readAsStringSync().contains('// test_shards: alone');

/// `../` steps from [dir] up to test/ ([dir] is inside it).
String _relativeUp(Directory dir) {
  final rel = dir.absolute.path.substring(Directory('test').absolute.path.length);
  final depth = rel.split('/').where((s) => s.isNotEmpty && s != '.').length;
  return '../' * depth;
}

String _shardSource(List<String> files, List<String> tags, Uri testDir, String toTest) {
  final b = StringBuffer()
    ..writeln('// Generated by tool/test_shards.dart for tool/test.sh: do not edit.');
  if (tags.isNotEmpty) {
    b
      ..writeln("@Tags([${tags.map((t) => "'$t'").join(', ')}])")
      ..writeln('library;');
  }
  b
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln("import 'package:len/ink/render/pattern_text.dart';")
    ..writeln();
  for (final (i, f) in files.indexed) {
    b.writeln("import '$toTest$f' as t$i;");
  }
  b
    ..writeln()
    ..writeln('void main() {');
  for (final (i, f) in files.indexed) {
    final golden = testDir.resolve(f);
    b
      ..writeln("  group('$f', () {")
      ..writeln(
        '    setUpAll(() {\n'
        "      goldenFileComparator = LocalFileComparator(Uri.parse('$golden'));\n"
        '      PatternText.debugClearCache();\n'
        '    });',
      )
      ..writeln('    t$i.main();')
      ..writeln('  });');
  }
  b.writeln('}');
  return b.toString();
}

Map<String, double> _readTimes() {
  final file = File(_timesPath);
  if (!file.existsSync()) return {};
  return (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).map(
    (k, v) => MapEntry(k, (v! as num).toDouble()),
  );
}

/// Updates tool/test_times.json with each file's time in the given
/// `--file-reporter json:` reports (of shard runs or plain runs): the sum
/// of its tests' times, set-up included.
void record(List<String> reports) {
  final times = _readTimes();
  final measured = <String, double>{};
  for (final report in reports) {
    final suites = <int, String>{};
    final starts = <int, (int, String)>{};
    for (final line in File(report).readAsLinesSync()) {
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;
      final e = decoded;
      switch (e['type']) {
        case 'suite':
          final s = e['suite']! as Map<String, Object?>;
          suites[s['id']! as int] = s['path']! as String;
        case 'testStart':
          final t = e['test']! as Map<String, Object?>;
          final name = t['name']! as String;
          if (name.startsWith('loading ')) continue;
          final suite = suites[t['suiteID']! as int] ?? '';
          final inShard = RegExp(r'^(\S+_test\.dart)( |$)').firstMatch(name);
          final file = inShard != null
              ? inShard[1]!
              : suite.contains('/test/')
              ? suite.substring(suite.lastIndexOf('/test/') + 6)
              : null;
          if (file == null) continue;
          starts[t['id']! as int] = (e['time']! as int, file);
        case 'testDone':
          final start = starts.remove(e['testID']! as int);
          if (start == null) continue;
          final (at, file) = start;
          measured[file] = (measured[file] ?? 0) + ((e['time']! as int) - at) / 1000;
      }
    }
  }
  for (final MapEntry(:key, :value) in measured.entries) {
    times[key] = double.parse(value.toStringAsFixed(1));
  }
  final existing = testFiles('all').toSet();
  final kept = Map.fromEntries(
    times.entries.where((e) => existing.contains(e.key)).toList()
      ..sort((a, b) => a.key.compareTo(b.key)),
  );
  File(_timesPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(kept)}\n');
  stdout.writeln('recorded ${measured.length} files in $_timesPath');
}
