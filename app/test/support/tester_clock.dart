import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';

/// The app clock on a widget test's fake time: `tester.pump(duration)`
/// moves it on, so budgets in minutes pass in the test, and nothing depends
/// on the wall clock (it starts at 2015-01-01 UTC).
class TesterClock extends Clock {
  const TesterClock();

  @override
  int nowMs() => TestWidgetsFlutterBinding.instance.clock.now().millisecondsSinceEpoch;
}

/// The app clock stopped at [at] (tests move it by hand): dates the app
/// shows don't depend on when the test runs (e.g. the days in this month
/// around midnight at its end).
class FixedClock extends Clock {
  FixedClock(this.at);

  DateTime at;

  @override
  int nowMs() => at.millisecondsSinceEpoch;
}
