import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/page_order.dart';
import 'package:len/data/page_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_actions.dart';
import 'package:len/features/editor/document/page_transfer.dart';

import 'support/property.dart';

/// A step that can be taken back, with the page lists before it.
typedef _Step = ({String what, void Function() undo, Map<String, List<String>> before});

/// Random page edits in a few notebooks, each checked against a reference
/// model (the page ids of each notebook in order), with linear undo.
class _Run {
  _Run(this.r) : s = AppServices.create(AppDatabase.inMemory()) {
    for (var i = 0; i < 3; i++) {
      final nb = s.notebooks.create(
        title: 'N$i',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      ids.add(nb.id);
      model[nb.id] = [for (final p in s.pages.pagesOf(nb.id)) p.id];
    }
  }

  final math.Random r;
  final AppServices s;
  final ids = <String>[];
  final model = <String, List<String>>{};
  final undo = <_Step>[];
  final log = <String>[];

  Map<String, List<String>> _snapshot() => {
    for (final e in model.entries) e.key: [...e.value],
  };

  /// An index biased to the start, so gaps between neighbouring keys run
  /// out and the notebook is renumbered.
  int _index(int length) =>
      r.nextInt(3) > 0 ? math.min(r.nextInt(3), length - 1) : r.nextInt(length);

  void step() {
    final nb = ids[r.nextInt(ids.length)];
    final actions = PageActions(s, nb);
    final pages = actions.pages;
    final before = _snapshot();
    void record(String what, void Function() undoIt) {
      log.add(what);
      undo.add((what: what, undo: undoIt, before: before));
    }

    final op = pages.isEmpty ? 0 : r.nextInt(r.nextInt(4) == 0 ? 8 : 7);
    switch (op) {
      case 7:
        // Many pages after the same one: the gap there runs out and the
        // notebook is renumbered.
        final after = pages.first;
        final added = [
          for (var i = 0; i < 34; i++)
            actions.add(specOf(const PageTemplate(paper: Paper.blank)), after: after),
        ];
        model[nb]!.insertAll(1, added.reversed.map((p) => p.id));
        record('34 pages after ${after.id}', () => actions.deleteAll(added));
      case 0 || 1:
        final after = pages.isEmpty || r.nextInt(5) == 0 ? null : pages[_index(pages.length)];
        final page = actions.add(specOf(const PageTemplate(paper: Paper.blank)), after: after);
        final list = model[nb]!;
        list.insert(after == null ? list.length : list.indexOf(after.id) + 1, page.id);
        record('add after ${after?.id}', () => actions.deleteAll([page]));
      case 2:
        final page = pages[_index(pages.length)];
        final copy = actions.duplicate(page);
        model[nb]!.insert(model[nb]!.indexOf(page.id) + 1, copy.id);
        record('duplicate ${page.id}', () => actions.deleteAll([copy]));
      case 3 || 4:
        final from = _index(pages.length), to = _index(pages.length);
        if (from == to) return;
        final page = pages[from];
        actions.move(page, to);
        model[nb]!
          ..removeAt(from)
          ..insert(to, page.id);
        record('move $from → $to', () => actions.move(page, from));
      case 5:
        final targets = {for (var i = 1 + r.nextInt(2); i > 0; i--) pages[_index(pages.length)]};
        final deleted = actions.deleteAll(targets.toList());
        model[nb]!.removeWhere((id) => targets.any((p) => p.id == id));
        record('delete ${targets.map((p) => p.id)}', () => actions.restoreAll(deleted));
      default:
        _transfer(nb, actions, pages, record);
    }
  }

  void _transfer(
    String nb,
    PageActions actions,
    List<NotebookPage> pages,
    void Function(String, void Function()) record,
  ) {
    final to = ids.firstWhere((id) => id != nb && r.nextBool(), orElse: () => ids.last);
    if (to == nb) return;
    final chosen = {for (var i = 1 + r.nextInt(2); i > 0; i--) r.nextInt(pages.length)}.toList()
      ..sort();
    final targets = [for (final i in chosen) actions.pages[i]];
    final copy = r.nextBool();
    final transfer = PageTransfer(
      actions: actions,
      pages: targets,
      open: () => to,
      made: false,
      copy: copy,
    );
    final before = {...model[to]!};
    transfer.send();
    final arrived = s.pages.pagesOf(to);
    model[to]!.addAll(arrived.skip(arrived.length - targets.length).map((p) => p.id));
    if (!copy) model[nb]!.removeWhere((id) => targets.any((p) => p.id == id));
    record('${copy ? 'copy' : 'move'} ${targets.map((p) => p.id)} to $to', () {
      // Copies moved or renumbered since count as changed, so undo keeps
      // them (never losing work, R8-1). Here they are thrown away after,
      // outside the model, which has the notebook as before the transfer.
      if (transfer.undo() == TransferKept.copies) {
        for (final p in s.pages.pagesOf(to)) {
          if (!before.contains(p.id)) s.notebooks.deletePage(p.id);
        }
      }
    });
  }

  void takeBack() {
    final last = undo.removeLast();
    log.add('undo ${last.what}');
    last.undo();
    for (final e in last.before.entries) {
      model[e.key] = [...e.value];
    }
  }

  void check() {
    for (final nb in ids) {
      final pages = s.pages.pagesOf(nb);
      expect([for (final p in pages) p.id], model[nb], reason: 'pages of $nb');
      for (var i = 1; i < pages.length; i++) {
        expect(pages[i].sortKey, greaterThan(pages[i - 1].sortKey), reason: 'unique, ascending');
      }
    }
  }
}

void main() {
  test('random adds, moves, deletes and transfers match a reference list; undo restores', () async {
    await forAll(
      Gens.intIn(0, 1 << 30),
      (seed) {
        final run = _Run(math.Random(seed));
        try {
          for (var i = 0; i < 60; i++) {
            if (run.undo.isNotEmpty && run.r.nextInt(4) == 0) {
              run.takeBack();
            } else {
              run.step();
            }
            run.check();
          }
          // Everything taken back: the notebooks as they began.
          while (run.undo.isNotEmpty) {
            run.takeBack();
            run.check();
          }
        } on TestFailure catch (e) {
          fail('${run.log.join('\n')}\n$e');
        } finally {
          run.s.dispose();
        }
      },
      runs: 40,
      seed: 1,
    );
  });

  test('a move rewrites only the moved key, unless the gap ran out', () async {
    await forAll(
      (r) {
        final keys = <double>[1];
        for (var i = r.nextInt(8); i > 0; i--) {
          keys.add(keys.last + (r.nextBool() ? 1 : PageOrder.minGap * (1 + r.nextInt(3))));
        }
        return (keys, r.nextInt(keys.length), r.nextInt(keys.length));
      },
      (c) {
        final (keys, from, to) = c;
        final key = PageOrder.forMove(keys, from, to);
        if (key == null) return;
        final rest = [...keys]..removeAt(from);
        final moved = [...rest]..insert(to, key);
        for (var i = 1; i < moved.length; i++) {
          expect(moved[i], greaterThan(moved[i - 1]));
        }
      },
      runs: 2000,
      seed: 2,
    );
  });

  test('spread gives increasing keys strictly between its bounds', () async {
    await forAll(
      (r) {
        final before = r.nextBool() ? null : r.nextDouble() * 10 - 5;
        final after = r.nextBool()
            ? null
            : (before ?? 0) + (r.nextBool() ? r.nextDouble() * 3 : r.nextDouble() * 1e-7);
        return (before, after, r.nextInt(6));
      },
      (c) {
        final (before, after, count) = c;
        final keys = PageOrder.spread(before, after, count);
        if (keys == null) {
          expect(after, isNotNull, reason: 'only a bounded gap runs out');
          return;
        }
        expect(keys, hasLength(count));
        final all = [?before, ...keys, ?after];
        for (var i = 1; i < all.length; i++) {
          expect(all[i], greaterThan(all[i - 1]));
        }
      },
      runs: 2000,
      seed: 3,
    );
  });
}
