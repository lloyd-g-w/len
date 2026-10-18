part of 'random_edits.dart';

/// The newer kinds of content [RandomEdits] makes: imported fonts (and
/// text using them, with paragraph spacing), version history (saved,
/// restored whole or by page, copied, renamed, deleted and brought back),
/// and shapes with connectors (boxes, curves, arrows attached to them;
/// boxes moved taking their arrows along, arrows recoloured).
extension _ContentEdits on RandomEdits {
  FontRepository get _fontStore => s.sync.engine.repositories.fonts;

  List<String> get _fonts => _ids('SELECT id FROM fonts WHERE deleted = 0 ORDER BY id');

  /// A font imported (a new file, or one imported before on some device,
  /// reviving it if removed), or removed.
  Future<void> font() async {
    final fonts = _fonts;
    if (fonts.isNotEmpty && r.nextInt(3) == 0) {
      _fontStore.remove(_pick(fonts));
      return;
    }
    // A small pool of files, so devices import the same one too.
    final bytes = Uint8List.fromList([
      0, 1, 0, 0, // sfnt
      for (var i = 0; i < 64; i++) (r.nextInt(6) * 31 + i) & 0xff,
    ]);
    final known = RandomEdits.fontFiles;
    final file = known.isNotEmpty && r.nextBool() ? _pick(known) : bytes;
    if (!known.any((k) => _same(k, file))) known.add(file);
    final sha = await s.blobs.putBytes(file, mime: 'font/ttf');
    _fontStore.add(name: 'f${r.nextInt(100)}', blob: sha);
  }

  static bool _same(Uint8List a, Uint8List b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  /// A text font for a new box: bundled, or (sometimes) an imported one,
  /// live here or not (removed, or a file never seen here).
  TextFont _textFont() {
    final fonts = _fonts;
    return switch (r.nextInt(4)) {
      0 when fonts.isNotEmpty => TextFont.user(_pick(fonts)),
      1 => TextFont.user(r.nextInt(1 << 30).toRadixString(16).padLeft(32, 'a')),
      _ => _pick(TextFont.bundled),
    };
  }

  List<String> get _versionedNotebooks => _ids(
    'SELECT DISTINCT notebook_id AS id FROM versions WHERE deleted = 0 AND notebook_id IN '
    '(SELECT id FROM notebooks WHERE deleted = 0 AND trashed_at IS NULL) ORDER BY id',
  );

  /// A version saved (named, or automatic) or restored (whole, a page, or
  /// as a copy), renamed, deleted or brought back.
  Future<void> version() async {
    final versioned = _versionedNotebooks;
    final v = s.versions;
    if (versioned.isEmpty || r.nextInt(3) == 0) {
      final notebooks = _notebooks;
      if (notebooks.isEmpty) return newNotebook();
      final nb = _pick(notebooks);
      if (r.nextBool()) {
        await v.save(nb, name: 'v${r.nextInt(100)}');
      } else {
        await v.record(nb);
      }
      return;
    }
    final versions = v.of(_pick(versioned));
    final version = _pick(versions);
    try {
      switch (r.nextInt(6)) {
        case 0 || 1:
          await v.restore(version);
        case 2:
          final body = await v.content.body(version);
          if (body.pages.isEmpty) {
            await v.restore(version);
          } else {
            await v.restorePage(version, _pick(body.pages).id);
          }
        case 3:
          await v.copy(version, title: 'copy ${r.nextInt(100)}');
        case 4:
          v.rename(version.id, r.nextBool() ? '' : 'v${r.nextInt(100)}');
        default:
          final gone = [version];
          v.delete([version.id]);
          if (r.nextBool()) v.undelete(gone);
      }
    } on VersionUnavailable {
      // Its files are not to be had (not uploaded yet, offline): no change.
    }
  }

  /// Live closed shapes on [surface] (connector targets).
  List<Stroke> _shapesOn(String surface) => [
    for (final x in SurfaceCopier(s.strokes).loadAll(surface))
      if (x.shape?.isClosed ?? false) x,
  ];

  List<Stroke> _linesOn(String surface) => [
    for (final x in SurfaceCopier(s.strokes).loadAll(surface))
      if (x.shape case final shape?
          when shape.kind == ShapeKind.line || shape.kind == ShapeKind.arrow)
        x,
  ];

  Stroke _shapeStroke(String surface, ShapeGeometry shape, {int? color}) => Stroke(
    id: s.clock.newId(),
    surfaceId: surface,
    tool: InkTool.ballpoint,
    color: color ?? 0xFF000000 + r.nextInt(0xFFFFFF),
    width: 2,
    points: ShapeBuilder.pointsOf(shape),
    createdAt: s.clock.nowMs(),
    style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
    shape: shape,
  );

  /// A shape drawn (a box, an ellipse, a closed curve), an arrow drawn
  /// from it to another, a shape moved with the lines attached to it (one
  /// edit), or a line recoloured (replaced, keeping its shape id).
  Future<void> connector() async {
    final surfaces = _surfaces;
    if (surfaces.isEmpty) return newNotebook();
    final surface = _pick(surfaces);
    final shapes = _shapesOn(surface);
    Offset at() => Offset(r.nextDouble() * 700, r.nextDouble() * 1000);
    switch (shapes.isEmpty ? 0 : r.nextInt(5)) {
      case 0:
        final a = at();
        final shape = switch (r.nextInt(3)) {
          0 => ShapeBuilder.dragged(ShapeKind.rectangle, a, a + const Offset(120, 80)),
          1 => ShapeBuilder.dragged(ShapeKind.ellipse, a, a + const Offset(90, 60)),
          _ => ShapeGeometry(ShapeKind.curve, [
            for (final p in [a, a + const Offset(60, 0), a + const Offset(60, 60)]) ...[
              p,
              p + const Offset(10, 10),
              p + const Offset(-10, 10),
            ],
          ]),
        };
        s.strokes.save([_shapeStroke(surface, shape)]);
      case 1:
        final from = _pick(shapes), to = _pick(shapes);
        final tail = ShapeAttachment(from.shapeId, r.nextDouble());
        final tip = ShapeAttachment(to.shapeId, r.nextDouble());
        final line = ShapeGeometry(
          r.nextBool() ? ShapeKind.arrow : ShapeKind.line,
          [ShapeAnchors.pointAt(from.shape!, tail.at), ShapeAnchors.pointAt(to.shape!, tip.at)],
          tail: r.nextBool() ? tail : null,
          tip: tip,
        );
        s.strokes.save([_shapeStroke(surface, line)]);
      case 2 || 3:
        // The app's move: the shape replaced (same shape id), and every
        // line attached to it moved along, in one change.
        final box = _pick(shapes);
        final by = Offset(r.nextDouble() * 80 - 40, r.nextDouble() * 80 - 40);
        final moved = box.shape!.map((p) => p + by).withOrigin(box.shapeId);
        final newBox = ShapeBuilder.reshaped(box, moved, id: s.clock.newId());
        final lines = [
          for (final line in _linesOn(surface))
            if (line.shape!.tail?.id == box.shapeId || line.shape!.tip?.id == box.shapeId) line,
        ];
        final follow = [
          for (final line in lines)
            Connectors.rebuilt(
              line,
              Connectors.follow(line.shape!, {box.shapeId: moved}).withOrigin(line.shapeId),
              id: s.clock.newId(),
            ),
        ];
        s.database.transaction(() {
          s.strokes.delete([box.id, for (final l in lines) l.id]);
          s.strokes.save([newBox, ...follow]);
        });
      default:
        final lines = _linesOn(surface);
        if (lines.isEmpty) return;
        final line = _pick(lines);
        final recoloured = Stroke(
          id: s.clock.newId(),
          surfaceId: surface,
          tool: line.tool,
          color: 0xFF000000 + r.nextInt(0xFFFFFF),
          width: line.width,
          points: line.points,
          createdAt: line.createdAt,
          style: line.style,
          shape: line.shape!.withOrigin(line.shapeId),
        );
        s.database.transaction(() {
          s.strokes.delete([line.id]);
          s.strokes.save([recoloured]);
        });
    }
    _touch(surface);
  }
}
