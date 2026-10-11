import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/segment_label.dart';
import 'page_setup.dart';
import 'template_catalog.dart';

/// The planner calendar new planners start with: the one chosen last, else
/// the device locale's language (if offered, else English) and its
/// customary week start.
PlannerCalendar defaultPlannerCalendar(BuildContext context) {
  final remembered = AppScope.maybeRead(context)?.settings.plannerCalendar;
  if (remembered != null) return remembered;
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  return PlannerCalendar.forLocale(locale.languageCode, locale.countryCode);
}

/// Dates and calendar of a planner template. When [generate] is set (new
/// notebooks, adding pages): the first month, how many months, and for
/// the monthly calendar whether linked week and day pages follow each
/// month and whether a year overview comes first. Otherwise (changing a
/// page's template): the one period the page shows. Always: the day weeks
/// start on and the language (remembered for the next planner).
class PlannerOptions extends StatelessWidget {
  const PlannerOptions({
    super.key,
    required this.selection,
    required this.generate,
    required this.onChanged,
  });

  final TemplateSelection selection;
  final bool generate;
  final ValueChanged<TemplateSelection> onChanged;

  PaperStyle get _style => selection.style;

  void _setPlan(PlannerPlan plan) => onChanged(
    selection.copyWith(
      plan: plan,
      template: selection.template.copyWith(
        paper: Paper.planner(_style, plan.start, calendar: plan.calendar),
      ),
    ),
  );

  void _setDate(DateTime date) => onChanged(
    selection.copyWith(
      template: selection.template.copyWith(
        paper: Paper.planner(_style, date, calendar: selection.plan.calendar),
      ),
    ),
  );

  void _setCalendar(BuildContext context, PlannerCalendar calendar) {
    AppScope.maybeRead(context)?.settings.plannerCalendar = calendar;
    final plan = selection.plan.copyWith(calendar: calendar);
    final date = generate ? plan.start : selection.template.paper.date ?? plan.start;
    onChanged(
      selection.copyWith(
        plan: plan,
        template: selection.template.copyWith(
          paper: Paper.planner(_style, date, calendar: calendar),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (generate) ..._range(context) else ..._date(),
        const SizedBox(height: Gaps.md),
        _CalendarRow(calendar: selection.plan.calendar, onChanged: (c) => _setCalendar(context, c)),
        if (generate && _style.period == PlannerPeriod.month) ..._monthSwitches(context),
      ],
    );
  }

  List<Widget> _date() {
    final period = _style.period!;
    final paper = selection.template.paper;
    final date = paper.date ?? selection.plan.start;
    return [
      const PickerLabel('Date'),
      _Stepper(
        key: const ValueKey('planner-date'),
        label: paper.period,
        onPrevious: () => _setDate(PlannerDates.step(period, date, -1)),
        onNext: () => _setDate(PlannerDates.next(period, date)),
      ),
    ];
  }

  List<Widget> _range(BuildContext context) {
    final plan = selection.plan;
    final pages = selection.pagesToCreate().length;
    return [
      PickerLabel('Dates', trailing: pages == 1 ? '1 page' : '$pages pages'),
      Wrap(
        spacing: Gaps.lg,
        runSpacing: Gaps.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Stepper(
            key: const ValueKey('planner-month'),
            label: PlannerLabels.of(plan.calendar.language).monthYear(plan.start),
            previousTooltip: 'Previous month',
            nextTooltip: 'Next month',
            onPrevious: () =>
                _setPlan(plan.copyWith(start: PlannerDates.addMonths(plan.start, -1))),
            onNext: () => _setPlan(plan.copyWith(start: PlannerDates.addMonths(plan.start, 1))),
          ),
          _Stepper(
            key: const ValueKey('planner-months'),
            label: plan.months == 1 ? '1 month' : '${plan.months} months',
            previousIcon: Icons.remove_rounded,
            nextIcon: Icons.add_rounded,
            previousTooltip: 'Fewer months',
            nextTooltip: 'More months',
            onPrevious: plan.months > 1
                ? () => _setPlan(plan.copyWith(months: plan.months - 1))
                : null,
            onNext: plan.months < PlannerPlan.maxMonths
                ? () => _setPlan(plan.copyWith(months: plan.months + 1))
                : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _monthSwitches(BuildContext context) {
    final plan = selection.plan;
    return [
      const SizedBox(height: Gaps.sm),
      SwitchListTile(
        key: const ValueKey('planner-linked'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: plan.linked,
        onChanged: (v) => _setPlan(plan.copyWith(linked: v)),
        title: const Text('Add week and day pages'),
        subtitle: Text(
          'Tap a day or week on the calendar to jump to its page',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      SwitchListTile(
        key: const ValueKey('planner-year'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: plan.yearOverview,
        onChanged: (v) => _setPlan(plan.copyWith(yearOverview: v)),
        title: const Text('Start with a year overview'),
      ),
    ];
  }
}

/// "Week starts on" (Monday / Sunday) and "Language", side by side when
/// there is room.
class _CalendarRow extends StatelessWidget {
  const _CalendarRow({required this.calendar, required this.onChanged});

  final PlannerCalendar calendar;
  final ValueChanged<PlannerCalendar> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Gaps.xl,
      runSpacing: Gaps.md,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PickerLabel('Week starts on'),
            ShrinkToFit(
              child: SegmentedButton<WeekStart>(
                key: const ValueKey('planner-week-start'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: WeekStart.monday, label: SegmentLabel('Monday')),
                  ButtonSegment(value: WeekStart.sunday, label: SegmentLabel('Sunday')),
                ],
                selected: {calendar.weekStart},
                onSelectionChanged: (s) => onChanged(calendar.copyWith(weekStart: s.single)),
              ),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PickerLabel('Language'),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xs),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<PlannerLanguage>(
                      key: const ValueKey('planner-language'),
                      value: calendar.language,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(Radii.control),
                      items: [
                        for (final l in PlannerLanguage.values)
                          DropdownMenuItem(
                            value: l,
                            child: Text(l.nativeName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (l) {
                        if (l != null) onChanged(calendar.copyWith(language: l));
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `‹ October 2026 ›`: a value between two step buttons.
class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.previousIcon = Icons.chevron_left_rounded,
    this.nextIcon = Icons.chevron_right_rounded,
    this.previousTooltip = 'Previous',
    this.nextTooltip = 'Next',
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final IconData previousIcon;
  final IconData nextIcon;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: previousTooltip,
            icon: Icon(previousIcon),
            onPressed: onPrevious,
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: nextTooltip,
            icon: Icon(nextIcon),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
