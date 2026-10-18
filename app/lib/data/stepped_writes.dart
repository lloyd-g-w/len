import 'dart:async';
import 'dart:collection';

import 'app_database.dart';

/// Writes run in steps across event-loop turns, all inside one transaction
/// of their [AppDatabase], so a large edit written after its frame (a
/// drag's commit rewriting hundreds of lines) takes no long turn and still
/// commits whole or not at all.
///
/// Each turn runs steps until [budget] has passed (at least one); the
/// transaction commits after the last. Anything else wanting the
/// connection for a transaction of its own ([AppDatabase.transaction],
/// [AppDatabase.close]) first [finish]es it, so it never joins half an
/// edit; reads between the turns see the steps run so far.
class SteppedWrites {
  SteppedWrites(this._database);

  final AppDatabase _database;

  /// The time a turn may spend on steps.
  static const budget = Duration(milliseconds: 4);

  final _steps = Queue<void Function()>();
  Timer? _timer;
  bool _open = false;
  bool _running = false;

  /// Whether a transaction of steps is open (begun, not committed).
  bool get isOpen => _open;

  /// Whether steps are running now (their own transactions join).
  bool get isRunning => _running;

  /// The time each turn of the last transaction took (µs), for benchmarks.
  final List<int> turns = [];

  /// Adds [steps] to the open transaction (beginning one if none) and runs
  /// as many as [budget] allows now, the rest in later turns. Inside a
  /// transaction not of steps, runs them all now (they join it).
  void add(Iterable<void Function()> steps) {
    if (!_open && !_database.db.autocommit) {
      for (final step in steps) {
        step();
      }
      return;
    }
    _steps.addAll(steps);
    if (_steps.isEmpty) return;
    if (!_open) {
      turns.clear();
      _database.writeSignal?.begin();
      try {
        _database.db.execute('BEGIN IMMEDIATE');
      } catch (_) {
        _steps.clear();
        _database.writeSignal?.end();
        rethrow;
      }
      _open = true;
    }
    _run(budget);
  }

  /// Runs the remaining steps now and commits.
  void finish() {
    if (!_open || _running) return;
    _run(null);
  }

  void _run(Duration? budget) {
    _timer?.cancel();
    _timer = null;
    final watch = Stopwatch()..start();
    _running = true;
    try {
      do {
        _steps.removeFirst()();
      } while (_steps.isNotEmpty && (budget == null || watch.elapsed < budget));
    } catch (_) {
      _running = false;
      _steps.clear();
      _close(commit: false);
      rethrow;
    }
    _running = false;
    turns.add(watch.elapsedMicroseconds);
    if (_steps.isEmpty) {
      _close(commit: true);
    } else {
      _timer = Timer(Duration.zero, () => _run(SteppedWrites.budget));
    }
  }

  void _close({required bool commit}) {
    _open = false;
    try {
      // Some errors (a full disk, a trigger's RAISE(ROLLBACK)) roll back
      // already.
      if (!_database.db.autocommit) _database.db.execute(commit ? 'COMMIT' : 'ROLLBACK');
    } finally {
      _database.writeSignal?.end();
    }
  }
}
