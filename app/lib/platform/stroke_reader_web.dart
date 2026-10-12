import '../data/sliced_stroke_reader.dart';
import '../data/stroke_reader.dart';
import '../data/stroke_repository.dart';

/// Browsers read on the UI thread, in time-budgeted slices over the app's
/// own connection (a Web Worker cannot share the in-memory IndexedDB-backed
/// database; see ARCHITECTURE, *Platforms*).
StrokeReader openStrokeReader(String? databasePath, {required StrokeReader fallback}) =>
    fallback is StrokeRepository ? SlicedStrokeReader(fallback.queries) : fallback;

/// Nothing to stop.
void closeStrokeReader(StrokeReader reader) {}
