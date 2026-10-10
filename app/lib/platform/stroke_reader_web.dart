import '../data/stroke_reader.dart';

/// Browsers read on the UI thread: [fallback] (the app's own connection).
StrokeReader openStrokeReader(String? databasePath, {required StrokeReader fallback}) => fallback;

/// Nothing to stop.
void closeStrokeReader(StrokeReader reader) {}
