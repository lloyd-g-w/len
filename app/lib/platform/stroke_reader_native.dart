import '../data/background_stroke_reader.dart';
import '../data/stroke_reader.dart';

/// A background-isolate reader over the database file at [databasePath],
/// or [fallback] for in-memory databases (no second connection possible).
StrokeReader openStrokeReader(String? databasePath, {required StrokeReader fallback}) =>
    databasePath == null ? fallback : BackgroundStrokeReader(databasePath, fallback: fallback);

/// Stops [reader]'s worker isolate, if it has one.
void closeStrokeReader(StrokeReader reader) {
  if (reader case final BackgroundStrokeReader worker) worker.close();
}
