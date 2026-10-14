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
