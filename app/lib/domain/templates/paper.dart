import 'paper_style.dart';
import 'planner_dates.dart';

/// The template of one page: a [style] plus what that style needs — the
/// [date] of a planner page or the [image] blob of a user's template.
///
/// Stored and synced as the style's name (`paper`) and [toData]
/// (`paperData`).
class Paper {
  const Paper._(this.style, {this.date}) : image = null;

  /// A template without parameters; for planners and images use
  /// [Paper.planner] / [Paper.image].
  const Paper(this.style) : date = null, image = null;

  /// A page of planner [style] for the period containing [date].
  Paper.planner(this.style, DateTime date)
    : assert(style.isPlanner),
      date = PlannerDates.periodStart(style.period!, date),
      image = null;

  /// A user's template: the image stored as blob [blob], stretched over the
  /// page.
  const Paper.image(String blob) : style = PaperStyle.image, date = null, image = blob;

  static const Paper blank = Paper(PaperStyle.blank);

  final PaperStyle style;

  /// Planners: the first day of the page's period (UTC midnight).
  final DateTime? date;

  /// [PaperStyle.image]: SHA-256 (lowercase hex) of the image blob.
  final String? image;

  /// [style] made concrete with default parameters: planners for the
  /// period containing [today]. Null for [PaperStyle.image] (it needs a
  /// blob).
  static Paper? defaultFor(PaperStyle style, {required DateTime today}) {
    if (style == PaperStyle.image) return null;
    return style.isPlanner ? Paper.planner(style, today) : Paper(style);
  }

  /// The same template for the following period (planners), else itself:
  /// what a page added after this one gets.
  Paper get next {
    final period = style.period;
    final date = this.date;
    if (period == null || date == null) return this;
    return Paper._(style, date: PlannerDates.next(period, date));
  }

  /// The parameters as stored (`paperData`).
  Map<String, Object?> toData() => {
    if (date != null) 'date': PlannerDates.encode(date!),
    if (image != null) 'image': image,
  };

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Parses stored parameters for [style]; null when they are missing or
  /// malformed (planners need a `date`, images an `image` blob id).
  static Paper? fromData(PaperStyle style, Map<String, Object?> data) {
    if (style.isPlanner) {
      final raw = data['date'];
      final date = raw is String ? PlannerDates.decode(raw) : null;
      if (date == null) return null;
      return Paper.planner(style, date);
    }
    if (style == PaperStyle.image) {
      final blob = data['image'];
      return blob is String && _sha256.hasMatch(blob) ? Paper.image(blob) : null;
    }
    return Paper(style);
  }

  /// A short description for pickers and menus, e.g. `Weekly planner ·
  /// Week 41 · 5 – 11 October 2026`.
  String get label {
    final period = style.period;
    final date = this.date;
    if (period == null || date == null) return style.label;
    return '${style.label} · ${PlannerDates.describe(period, date)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Paper && other.style == style && other.date == date && other.image == image;

  @override
  int get hashCode => Object.hash(style, date, image);

  @override
  String toString() => 'Paper(${style.name}, ${toData()})';
}
