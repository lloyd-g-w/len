part of 'surface_model.dart';

/// Models with edits waiting for [_SurfaceState.writeBehind].
final Set<_SurfaceState> _withUnsaved = {};

/// What a [SurfaceModel] holds: its settings, the loaded strokes and
/// elements with their chunk indexes, and the change stream; plus the
/// internals its parts share.
abstract class _SurfaceState extends ChangeNotifier {
  _SurfaceState({
    required this.surfaceId,
    required this._repository,
    this._elementRepository,
    this.images,
    StrokeReader? reader,
    this.maxLoadedChunks = 1024,
    this.clock = const Clock(),
    this.writeBehind = false,
    this.outlines,
  }) {
    _loading = SurfaceLoader(
      reader: reader ?? _repository,
      surfaceId: surfaceId,
      skipFor: _loadedWithin,
      onLoad: _onLoad,
    );
  }

  /// Creates ids for strokes made by editing (pixel-eraser fragments).
  final Clock clock;

  final String surfaceId;
  final StrokeRepository _repository;

  /// Element storage; without it the surface holds ink only.
  final ElementRepository? _elementRepository;

  /// Decoded bitmaps for image elements (null: images show placeholders).
  final ElementImages? images;

  /// Soft cap on loaded chunks before far-away ones are evicted.
  final int maxLoadedChunks;

  /// Whether stroke edits are written to storage right after the frame
  /// that shows them instead of during the edit, so committing a stroke
  /// stays cheap. Reads, [reload] and [dispose] [flush] first.
  final bool writeBehind;

  /// Stroke edits not written yet (see [writeBehind]).
  final List<InkEdit> _unsaved = [];

  /// Builds loaded strokes' outlines before they are added (off the UI
  /// thread), so the first frame drawing a page does not build thousands
  /// of them; null: built when first drawn.
  final OutlinePreparer? outlines;

  /// Bumped by [reload]: loads prepared before are dropped.
  int _generation = 0;

  // Indexed with the same chunk functions as storage (path-based for ink).
  final _strokes = ContentIndex<Stroke>(idOf: (s) => s.id, chunksOf: StrokeChunks.of);
  final _elements = ContentIndex<SurfaceElement>(idOf: (e) => e.id, chunksOf: ElementChunks.of);

  /// Chunks whose stored content is fully in memory.
  final Set<ChunkKey> _loaded = {};

  /// Ids of strokes / elements not drawn by the committed layer (because a
  /// selection or text editor shows them instead).
  Set<String> _hidden = const {};

  final UndoHistory history = UndoHistory();

  /// Called after every committed (undoable) edit, e.g. so a notebook-wide
  /// undo knows which page changed last.
  VoidCallback? onCommit;

  final _changes = StreamController<SurfaceChange>.broadcast(sync: true);

  late final SurfaceLoader _loading;
  bool _disposed = false;

  ChunkRange? _lastRange;
  Rect? _lastVisible;

  /// Emits chunks whose rendering is stale; `null` means "everything".
  Stream<Set<ChunkKey>?> get invalidations => _changes.stream.map((c) => c.chunks);

  /// Like [invalidations], but tells appended strokes apart (see
  /// [SurfaceChange.appended]), so raster caches can add them to what they
  /// already rendered instead of rendering again.
  Stream<SurfaceChange> get changes => _changes.stream;

  int get loadedStrokeCount => _strokes.length;
  int get loadedElementCount => _elements.length;

  int _preparing = 0;

  /// Ids removed while loads were being prepared: those loads must not
  /// bring them back.
  final Set<String> _removedWhilePreparing = {};

  /// Chunks read but not added yet (their outlines are being built): not
  /// read again meanwhile.
  final Set<ChunkKey> _arriving = {};

  /// The ids each owner hides (see [SurfaceModel.setHidden]).
  final Map<Object?, Set<String>> _hiddenBy = {};

  /// What owners hiding items draw in their place (see [LiftedContent]).
  final LiftedContent _lifted = LiftedContent();

  /// Writes stroke edits still waiting for [writeBehind] to storage.
  void flush();

  /// Loaded and arriving chunks within [range] (not to be read again).
  Set<ChunkKey> _loadedWithin(ChunkRange range);

  /// Adds what a background read brought in.
  void _onLoad(ChunkLoad load);

  /// Removals go through here so a background read in flight cannot bring
  /// back a stale copy (see [SurfaceLoader.noteRemoved]).
  void _removeStroke(Stroke stroke) {
    _strokes.remove(stroke);
    _loading.noteRemoved(stroke.id);
  }

  void _removeElement(SurfaceElement element) {
    _elements.remove(element);
    _loading.noteRemoved(element.id);
  }

  void _changed(
    Set<ChunkKey> chunks, {
    List<Stroke>? appended,
    bool loaded = false,
    List<Rect>? areas,
  }) {
    _changes.add(SurfaceChange(chunks, appended: appended, loaded: loaded, areas: areas));
    notifyListeners();
  }
}
