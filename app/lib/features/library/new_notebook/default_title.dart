import '../../../domain/templates/planner_calendar.dart';
import '../../../domain/templates/planner_labels.dart';

/// The title a notebook gets when none is typed: the day it was made in
/// the device's date format ("13 October", "October 13", "13. Oktober"),
/// numbered when that title is taken ("13 October (2)"), so a week of
/// quick notes can be told apart in the grid and in search.
String defaultNotebookTitle(
  DateTime today,
  Iterable<String> taken, {
  PlannerLanguage language = PlannerLanguage.enGB,
}) {
  final base = PlannerLabels.of(language).monthDay(today);
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  var n = 2;
  while (used.contains('$base ($n)')) {
    n++;
  }
  return '$base ($n)';
}
