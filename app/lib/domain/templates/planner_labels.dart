import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart';

import 'paper_style.dart';
import 'planner_calendar.dart';
import 'planner_dates.dart';
import 'planner_words.dart';

/// Month and day names, date formats and the fixed headings printed on
/// planner pages, in a [PlannerLanguage] (names and formats from `intl`'s
/// CLDR data, headings from [plannerWords]).
class PlannerLabels {
  PlannerLabels._(this.language) : _locale = language.intlLocale {
    ensureDateSymbols();
    _symbols = DateFormat('d', _locale).dateSymbols;
    _long = DateFormat.yMMMMd(_locale);
    _monthDay = DateFormat.MMMMd(_locale);
    _monthYear = DateFormat.yMMMM(_locale);
    _dayShort = DateFormat.yMMMEd(_locale);
  }

  /// The (cached) labels of [language].
  factory PlannerLabels.of(PlannerLanguage language) =>
      _cache[language] ??= PlannerLabels._(language);

  static final Map<PlannerLanguage, PlannerLabels> _cache = {};

  final PlannerLanguage language;
  late final PlannerWords words = plannerWords[language]!;
  final String _locale;
  late final DateSymbols _symbols;
  late final DateFormat _long, _monthDay, _monthYear, _dayShort;

  /// `October`, `Oktober`, `Октябрь` (standalone form, capitalised as a
  /// title).
  String monthName(int month) => capitalise(_symbols.STANDALONEMONTHS[month - 1]);

  /// `Monday`, `Montag`, `Понедельник` for a [DateTime.weekday].
  String weekdayName(int weekday) => capitalise(_symbols.STANDALONEWEEKDAYS[weekday % 7]);

  /// `MON`, `MO`, `ПН`: a short column heading (at most four letters).
  String weekdayShort(int weekday) {
    var s = _symbols.STANDALONESHORTWEEKDAYS[weekday % 7];
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.length > 4) s = s.substring(0, 3);
    return upper(s);
  }

  /// `M`, `П`: a one-letter heading for mini calendars.
  String weekdayNarrow(int weekday) => upper(_symbols.STANDALONENARROWWEEKDAYS[weekday % 7]);

  /// `Week 41`, `Woche 41`, `41. Hafta`.
  String week(int number) => words.week.replaceFirst('#', '$number');

  /// The month of the week from [start] (`October`), or of both months it
  /// spans (`Dec – Jan`, short names).
  String weekMonths(DateTime start) {
    final end = PlannerDates.addDays(start, 6);
    if (start.month == end.month) return monthName(start.month);
    String short(int month) => capitalise(_symbols.STANDALONESHORTMONTHS[month - 1]);
    return '${short(start.month)} – ${short(end.month)}';
  }

  /// `5 October 2026`, `October 5, 2026`, `5. Oktober 2026`.
  String longDate(DateTime d) => _long.format(d);

  /// `13 October`, `October 13`, `13. Oktober`: a day without the year.
  String monthDay(DateTime d) => _monthDay.format(d);

  /// `October 2026`, `Oktober 2026`, `Октябрь 2026 г.`.
  String monthYear(DateTime d) => capitalise(_monthYear.format(d));

  /// The seven days from [start]: `5 – 11 October 2026`, `October 5 – 11,
  /// 2026`, `28 September – 4 October 2026`, across years `29 December
  /// 2025 – 4 January 2026`.
  String weekRange(DateTime start) {
    final end = PlannerDates.addDays(start, 6);
    if (start.year != end.year) return '${longDate(start)} – ${longDate(end)}';
    if (start.month != end.month) return '${_monthDay.format(start)} – ${longDate(end)}';
    final pattern = _monthDay.pattern ?? '';
    if (pattern.startsWith('d')) {
      // Day first: the start's day alone (with its full stop, if any).
      final dot = pattern.length > 1 && pattern[1] == '.' ? '.' : '';
      return '${start.day}$dot – ${longDate(end)}';
    }
    if (pattern.startsWith('MMMM')) {
      // Month first: the end without the month.
      final month = _symbols.MONTHS[end.month - 1];
      final rest = longDate(end).replaceFirst(month, '').trim();
      return '${_monthDay.format(start)} – $rest';
    }
    return '${longDate(start)} – ${longDate(end)}';
  }

  /// A short label of the period starting at [start], e.g. `Sun, 11 Oct
  /// 2026`, `Week 41, 5 – 11 October 2026`, `October 2026`, `2026`.
  String describe(PlannerPeriod period, DateTime start, WeekStart weekStart) => switch (period) {
    PlannerPeriod.day => _dayShort.format(start),
    PlannerPeriod.week => '${week(PlannerDates.weekNumber(start, weekStart))}, ${weekRange(start)}',
    PlannerPeriod.month => monthYear(start),
    PlannerPeriod.year => '${start.year}',
  };

  /// [s] with its first letter upper case (month names are lower case in
  /// many languages, but stand as titles on planners).
  String capitalise(String s) {
    if (s.isEmpty) return s;
    final first = language == PlannerLanguage.tr && s[0] == 'i' ? 'İ' : s[0].toUpperCase();
    return first + s.substring(1);
  }

  /// [s] in capitals, following the language's rules where they differ
  /// from the default (Turkish dotted İ, Greek capitals without accents).
  String upper(String s) {
    if (language == PlannerLanguage.tr) s = s.replaceAll('i', 'İ');
    final u = s.toUpperCase();
    if (language != PlannerLanguage.el) return u;
    return u.replaceAllMapped(_greekAccented, (m) => _greekPlain[m[0]]!);
  }

  static final _greekAccented = RegExp('[ΆΈΉΊΌΎΏ]');
  static const _greekPlain = {'Ά': 'Α', 'Έ': 'Ε', 'Ή': 'Η', 'Ί': 'Ι', 'Ό': 'Ο', 'Ύ': 'Υ', 'Ώ': 'Ω'};
}
