import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_actions.dart';
import 'package:len/features/editor/document/page_edits.dart';
import 'package:len/features/editor/document/page_models.dart';
import 'package:len/features/editor/document/page_transfer.dart';

import 'data_test.dart' show stroke;

/// Undoing a page move or copy never deletes work done since (UX_AUDIT R8-1).
void main() {
  late AppServices s;
  late PageModels models;
  setUp(() {
    s = AppServices.create(AppDatabase.inMemory());
    models = PageModels();
  });
  tearDown(() {
    models.dispose();
    s.dispose();
  });

  Notebook paged(String title) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0,
  );

  List<String> pageIds(String notebook) => [for (final p in s.pages.pagesOf(notebook)) p.id];
  int inkOn(String page) => SurfaceCopier(s.strokes).loadAll(page).length;

  /// Sends the source's last two pages to [open]'s notebook as one step.
  ({PageEdit edit, List<TransferKept> kept}) send(
    Notebook source, {
    required String Function() open,
    bool made = false,
    bool copy = false,
  }) {
    final edits = PageEdits(actions: PageActions(s, source.id), models: models, shown: ({keep}) {});
    final kept = <TransferKept>[];
    final edit = edits.sendTo(
      s.pages.pagesOf(source.id).skip(1).toList(),
      open: open,
      made: made,
      copy: copy,
      changed: (_, _) {},
      kept: (_, k) => kept.add(k),
    );
    return (edit: edit, kept: kept);
  }

  Notebook source3() {
    final source = paged('Physics');
    s.pages.addPage(source.id);
    s.pages.addPage(source.id);
    return source;
  }

  test('an untouched move undoes completely and redoes', () {
    final source = source3(), target = paged('Biology');
    final original = pageIds(source.id);
    final sent = send(source, open: () => target.id);
    expect(pageIds(target.id), hasLength(3));

    models.undo();
    expect(pageIds(source.id), original);
    expect(pageIds(target.id), hasLength(1));
    expect(sent.kept, isEmpty);

    models.redo();
    expect(pageIds(source.id), [original.first]);
    expect(pageIds(target.id), hasLength(3));
  });

  test('undo after writing on a moved page keeps that page in the destination', () {
    final source = source3(), target = paged('Biology');
    final original = pageIds(source.id);
    final sent = send(source, open: () => target.id);
    final copies = pageIds(target.id).skip(1).toList();
    s.strokes.save([stroke('later', const Offset(10, 10), surface: copies.last)]);

    models.undo();
    expect(pageIds(source.id), original); // The pages are back here…
    expect(pageIds(target.id).skip(1), copies); // …and the written copies stay.
    expect(inkOn(copies.last), 1);
    expect(sent.kept, [TransferKept.copies]);

    // Redo moves them there again, onto the very copies: nothing doubles.
    models.redo();
    expect(pageIds(source.id), [original.first]);
    expect(pageIds(target.id).skip(1), copies);
    expect(inkOn(copies.last), 1);

    models.undo();
    expect(pageIds(source.id), original);
    expect(inkOn(copies.last), 1);
  });

  test('undoing a copy keeps copies changed since', () {
    final source = source3(), target = paged('Biology');
    final sent = send(source, open: () => target.id, copy: true);
    final copy = pageIds(target.id).last;
    s.pages.setBookmarked(copy, true);

    models.undo();
    expect(pageIds(target.id), contains(copy));
    expect(sent.kept, [TransferKept.copies]);
    expect(pageIds(source.id), hasLength(3));
  });

  test('a new notebook goes to the Trash on undo, never deleted, and redo brings it back', () {
    final source = source3();
    final original = pageIds(source.id);
    var made = 0;
    late Notebook created;
    String open() {
      made++;
      created = s.notebooks.create(
        title: 'Forces',
        kind: NotebookKind.paged,
        paper: PaperStyle.dotted,
        coverColor: 0,
        empty: true,
      );
      return created.id;
    }

    final sent = send(source, open: open, made: true);
    final copies = pageIds(created.id);
    expect(copies, hasLength(2));
    s.strokes.save([stroke('later', const Offset(10, 10), surface: copies.first)]);
    final extra = s.pages.addPage(created.id); // A page added there too.

    models.undo();
    expect(pageIds(source.id), original);
    final trashed = s.notebooks.get(created.id)!;
    expect(trashed.isTrashed, isTrue);
    expect(pageIds(created.id), [...copies, extra.id]); // Everything is still in it.
    expect(inkOn(copies.first), 1);
    expect(sent.kept, [TransferKept.trashed]);

    models.redo();
    expect(made, 1); // The same notebook, out of the Trash.
    expect(s.notebooks.get(created.id)!.isTrashed, isFalse);
    expect(pageIds(source.id), [original.first]);
    expect(pageIds(created.id), [...copies, extra.id]);
    expect(inkOn(copies.first), 1);
  });

  test('an untouched new notebook goes to the Trash too; once emptied, redo makes another', () {
    final source = source3();
    final made = <String>[];
    String open() {
      final n = s.notebooks.create(
        title: 'Forces',
        kind: NotebookKind.paged,
        paper: PaperStyle.dotted,
        coverColor: 0,
        empty: true,
      );
      made.add(n.id);
      return n.id;
    }

    final sent = send(source, open: open, made: true);
    models.undo();
    expect(s.notebooks.get(made.single)!.isTrashed, isTrue);
    expect(sent.kept, isEmpty);
    s.notebooks.emptyTrash();

    models.redo();
    expect(made, hasLength(2));
    expect(pageIds(made.last), hasLength(2));
    expect(pageIds(source.id), hasLength(1));
  });
}
