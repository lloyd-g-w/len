import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_style.dart';
import 'package:len/domain/paper.dart';

import 'support/fake_server.dart';

class _Clock extends Clock {
  _Clock(this.prefix);

  final String prefix;
  int now = 1000;
  int _ids = 0;

  @override
  int nowMs() => now += 10;

  @override
  String newId() => '$prefix${_ids++}';
}

AppServices _device(String prefix) {
  final s = AppServices.create(AppDatabase.inMemory(), clock: _Clock(prefix));
  addTearDown(s.dispose);
  return s;
}

const _lecture = NotebookChoice(
  paper: PaperStyle.dotted,
  look: PaperLook(spacing: 5, margin: false),
  paperColor: PaperColor.cream,
  format: PageFormat.a5,
  orientation: PageOrientation.landscape,
  coverColor: 0xFF0CA678,
);

void main() {
  group('NotebookChoice', () {
    test('round-trips through JSON', () {
      expect(NotebookChoice.fromJson(_lecture.toJson()), _lecture);
      final canvas = NotebookChoice(
        kind: NotebookKind.canvas,
        paperColor: PaperColor.custom(0xFF223344),
        coverColor: 1,
      );
      expect(NotebookChoice.fromJson(canvas.toJson()), canvas);
    });

    test('rejects every missing or malformed field', () {
      final good = _lecture.toJson();
      for (final key in good.keys) {
        expect(NotebookChoice.fromJson({...good}..remove(key)), isNull, reason: 'no $key');
      }
      for (final (key, value) in [
        ('kind', 'scroll'),
        ('paper', 'image'),
        ('paper', 'papyrus'),
        ('look', {'spacing': 1}),
        ('paperColor', 'plaid'),
        ('format', 'a3'),
        ('orientation', 'sideways'),
        ('coverColor', 1.5),
      ]) {
        expect(NotebookChoice.fromJson({...good, key: value}), isNull, reason: '$key $value');
      }
    });

    test('of: a user image template is no style', () {
      expect(
        NotebookChoice.of(
          kind: NotebookKind.paged,
          template: PageTemplate(paper: Paper.image('a' * 64)),
          coverColor: 0,
        ),
        isNull,
      );
      final template = PageTemplate(
        paper: const Paper(PaperStyle.dotted, look: PaperLook(spacing: 5, margin: false)),
        color: PaperColor.cream,
        format: PageFormat.a5,
        orientation: PageOrientation.landscape,
      );
      expect(
        NotebookChoice.of(kind: NotebookKind.paged, template: template, coverColor: 0xFF0CA678),
        _lecture,
      );
    });
  });

  group('NotebookStyleRepository', () {
    test('create, rename, one default, delete', () {
      final repo = _device('a').notebookStyles;
      expect(repo.list(), isEmpty);
      expect(repo.defaultStyle(), isNull);
      final lecture = repo.create(name: 'Lecture', choice: _lecture);
      final sketch = repo.create(
        name: 'Sketch',
        choice: const NotebookChoice(kind: NotebookKind.canvas, coverColor: 2),
      );
      expect([for (final s in repo.list()) s.name], ['Lecture', 'Sketch']);
      expect(repo.get(lecture.id)!.choice, _lecture);

      repo.setDefault(lecture.id, isDefault: true);
      expect(repo.defaultStyle()!.id, lecture.id);
      repo.setDefault(sketch.id, isDefault: true);
      expect(repo.defaultStyle()!.id, sketch.id);
      expect(repo.get(lecture.id)!.isDefault, isFalse, reason: 'one default');
      repo.setDefault(sketch.id, isDefault: false);
      expect(repo.defaultStyle(), isNull);

      repo.rename(lecture.id, 'Lectures');
      expect(repo.get(lecture.id)!.name, 'Lectures');
      repo.setDefault(lecture.id, isDefault: true);
      repo.delete(lecture.id);
      expect(repo.get(lecture.id), isNull);
      expect(repo.defaultStyle(), isNull, reason: 'a deleted default is none');
      expect([for (final s in repo.list()) s.name], ['Sketch']);
    });

    test('preferences remember the last choice', () {
      final prefs = _device('a').preferences;
      expect(prefs.lastNotebookChoice, isNull);
      prefs.lastNotebookChoice = _lecture;
      expect(prefs.lastNotebookChoice, _lecture);
    });
  });

  group('sync', () {
    test('styles, renames, the default and deletions travel; malformed are skipped', () async {
      final server = FakeServer();
      final a = _device('a'), b = _device('b');
      Future<void> send(AppServices from, AppServices to) async {
        await from.sync.engine.sync(apiFor(server));
        await to.sync.engine.sync(apiFor(server));
      }

      final lecture = a.notebookStyles.create(name: 'Lecture', choice: _lecture);
      a.notebookStyles.setDefault(lecture.id, isDefault: true);
      await send(a, b);
      final got = b.notebookStyles.list().single;
      expect(got.name, 'Lecture');
      expect(got.choice, _lecture);
      expect(b.notebookStyles.defaultStyle()!.id, lecture.id);
      expect(server.stored('notebook_styles', lecture.id)!['data'], {
        'name': 'Lecture',
        'style': _lecture.toJson(),
        'isDefault': true,
        'createdAt': lecture.createdAt,
      });

      b.notebookStyles.rename(lecture.id, 'Lectures');
      b.notebookStyles.setDefault(lecture.id, isDefault: false);
      await send(b, a);
      expect(a.notebookStyles.get(lecture.id)!.name, 'Lectures');
      expect(a.notebookStyles.defaultStyle(), isNull);

      a.notebookStyles.delete(lecture.id);
      await send(a, b);
      expect(b.notebookStyles.list(), isEmpty);

      Map<String, Object?> record(String id, Map<String, Object?> data) => {
        'collection': 'notebook_styles',
        'id': id,
        'updatedAt': 10,
        'deviceId': 'remote',
        'deleted': false,
        'data': data,
      };
      final good = {'name': 'Good', 'style': _lecture.toJson(), 'isDefault': false, 'createdAt': 1};
      server.injected.addAll([
        record('no-name', {...good}..remove('name')),
        record('no-default', {...good}..remove('isDefault')),
        record('bad-style', {
          ...good,
          'style': {..._lecture.toJson(), 'paper': 'image'},
        }),
        record('style-string', {...good, 'style': 'dotted'}),
        record('good', good),
      ]);
      await b.sync.engine.sync(apiFor(server));
      expect([for (final s in b.notebookStyles.list()) s.id], ['good']);
    });
  });
}
