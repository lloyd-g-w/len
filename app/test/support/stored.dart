import 'package:len/app_services.dart';
import 'package:len/data/stroke_repository.dart';

/// [s]'s strokes as stored, read as the app's own readers read them: an
/// edit still being written in steps across turns (`SteppedWrites`: a
/// move, reshape or erase written after its frame) is finished first, as a
/// push or another transaction of the app finishes it.
///
/// A bare `tester.pump()` runs only the first turn's steps (the timer for
/// the rest fires only as fake time passes), and on a busy machine that
/// turn may end after a move's deletions, before its additions: reading
/// storage straight after it would find the moved strokes gone.
StrokeRepository storedStrokes(AppServices s) {
  s.database.steps.finish();
  return s.strokes;
}
