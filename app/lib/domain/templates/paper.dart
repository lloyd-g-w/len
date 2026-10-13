import 'paper_look.dart';
import 'paper_style.dart';
import 'planner_calendar.dart';
import 'planner_dates.dart';
import 'planner_labels.dart';

/// The template of one page: a [style] plus what that style needs — the
/// [date] and [calendar] of a planner page or the [image] blob of a user's
/// template — and how it is drawn ([look]).
///
/// Stored and synced as the style's name (`paper`) and [toData]
/// (`paperData`).
class Paper {
  const Paper._(this.style, {this.date, this.calendar, this.look = PaperLook.standard})
    : image = null;

  /// A template without parameters; for planners and images use
  /// [Paper.planner] / [Paper.image].
  const Paper(this.style, {this.look = PaperLook.standard})
    : date = null,
      calendar = null,
      image = null;

  /// A page of planner [style] for the period containing [date], with
  /// the weeks and labels of [calendar].
  Paper.planner(
    PaperStyle style,
    DateTime date, {
    PlannerCalendar calendar = PlannerCalendar.standard,
    PaperLook look = PaperLook.standard,
  }) : this._(
         style,
         date: PlannerDates.periodStart(style.period!, date, calendar.weekStart),
         calendar: calendar,
         look: look,
       );

  /// A user's template: the image stored as blob [blob], stretched over the
  /// page.
  const Paper.image(String blob, {this.look = PaperLook.standard})
    : style = PaperStyle.image,
      date = null,
      calendar = null,
      image = blob;

  static const Paper blank = Paper(PaperStyle.blank);

  final PaperStyle style;

  /// Planners: the first day of the page's period (UTC midnight).
  final DateTime? date;

  /// Planners: the week start and language.
  final PlannerCalendar? calendar;

  /// [PaperStyle.image]: SHA-256 (lowercase hex) of the image blob.
  final String? image;

  /// Spacing, weights, colours and extras.
  final PaperLook look;

  /// The pattern pitch in world units: the look's spacing where the style
  /// has an adjustable one, else the style's.
  double get pitch => switch ((look.spacing, style.pitchKind)) {
    (final mm?, _?) => mm * PaperLook.unitsPerMm,
    _ => style.spacing,
  };

  /// The same template drawn with [look].
  Paper withLook(PaperLook look) => switch (style) {
    PaperStyle.image => Paper.image(image!, look: look),
    _ when date != null => Paper._(style, date: date, calendar: calendar, look: look),
    _ => Paper(style, look: look),
  };

  /// Whether [other] is the same page of the same template, whatever its
  /// look: what planner links lead to.
  bool sameSheet(Paper other) =>
      other.style == style &&
      other.date == date &&
      other.calendar == calendar &&
      other.image == image;

  /// [style] made concrete with default parameters: planners for the
  /// period containing [today] in [calendar]. Null for [PaperStyle.image]
  /// (it needs a blob).
  static Paper? defaultFor(
    PaperStyle style, {
    required DateTime today,
    PlannerCalendar calendar = PlannerCalendar.standard,
  }) {
    if (style == PaperStyle.image) return null;
    return style.isPlanner ? Paper.planner(style, today, calendar: calendar) : Paper(style);
  }

  /// A planner page of [style] for the period containing [date] in the
  /// same calendar as this page: what its links lead to.
  Paper sibling(PaperStyle style, DateTime date) =>
      Paper.planner(style, date, calendar: calendar ?? PlannerCalendar.standard, look: look);

  /// The same template for the following period (planners), else itself:
  /// what a page added after this one gets.
  Paper get next {
    final period = style.period;
    final date = this.date;
    if (period == null || date == null) return this;
    return Paper._(style, date: PlannerDates.next(period, date), calendar: calendar, look: look);
  }

  /// The parameters as stored (`paperData`).
  Map<String, Object?> toData() => {
    if (date != null) 'date': PlannerDates.encode(date!),
    if (calendar case final c?) ...{'weekStart': c.weekStart.name, 'locale': c.language.tag},
    if (image != null) 'image': image,
    'look': look.toJson(),
  };

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Parses stored parameters for [style]; null when they are missing or
  /// malformed (planners need a `date`, `weekStart` and `locale`, images
  /// an `image` blob id, every template a `look`). Local data may lack the
  /// look (the column's default): with [requireLook] false it reads as
  /// standard.
  static Paper? fromData(PaperStyle style, Map<String, Object?> data, {bool requireLook = true}) {
    final rawLook = data['look'];
    final look = rawLook == null && !requireLook ? PaperLook.standard : PaperLook.fromJson(rawLook);
    if (look == null) return null;
    return _fromData(style, data)?.withLook(look);
  }

  static Paper? _fromData(PaperStyle style, Map<String, Object?> data) {
    if (style.isPlanner) {
      final raw = data['date'];
      final date = raw is String ? PlannerDates.decode(raw) : null;
      final weekStart = WeekStart.tryParse(data['weekStart']);
      final language = PlannerLanguage.tryParse(data['locale']);
      if (date == null || weekStart == null || language == null) return null;
      return Paper.planner(
        style,
        date,
        calendar: PlannerCalendar(weekStart: weekStart, language: language),
      );
    }
    if (style == PaperStyle.image) {
      final blob = data['image'];
      return blob is String && _sha256.hasMatch(blob) ? Paper.image(blob) : null;
    }
    return Paper(style);
  }

  /// The labels of a planner page (in its language).
  PlannerLabels get labels => PlannerLabels.of((calendar ?? PlannerCalendar.standard).language);

  /// The period a planner page shows, e.g. `Week 41, 5 – 11 October
  /// 2026`, in the page's language; the style's label for other
  /// templates.
  String get period {
    final period = style.period;
    final date = this.date;
    if (period == null || date == null) return style.label;
    return labels.describe(period, date, (calendar ?? PlannerCalendar.standard).weekStart);
  }

  /// A short description for pickers and menus, e.g. `Weekly planner,
  /// Week 41, 5 – 11 October 2026`.
  String get label => date == null ? style.label : '${style.label}, $period';

  @override
  bool operator ==(Object other) =>
      other is Paper &&
      other.style == style &&
      other.date == date &&
      other.calendar == calendar &&
      other.image == image &&
      other.look == look;

  @override
  int get hashCode => Object.hash(style, date, calendar, image, look);

  @override
  String toString() => 'Paper(${style.name}, ${toData()})';
}
