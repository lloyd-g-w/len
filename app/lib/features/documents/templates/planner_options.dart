import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ui/app_theme.dart';
import 'page_setup.dart';
import 'template_catalog.dart';

/// Dates of a planner template. When [generate] is set (new notebooks,
/// adding pages): the first month, how many months, and for the monthly
/// calendar whether linked week and day pages follow each month. Otherwise
/// (changing a page's template): the one period the page shows.
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
      template: selection.template.copyWith(paper: Paper.planner(_style, plan.start)),
    ),
  );

  void _setDate(DateTime date) => onChanged(
    selection.copyWith(template: selection.template.copyWith(paper: Paper.planner(_style, date))),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = selection.plan;
    if (!generate) {
      final period = _style.period!;
      final date = selection.template.paper.date ?? plan.start;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PickerLabel('Date'),
          _Stepper(
            key: const ValueKey('planner-date'),
            label: PlannerDates.describe(period, date),
            onPrevious: () => _setDate(_previous(period, date)),
            onNext: () => _setDate(PlannerDates.next(period, date)),
          ),
        ],
      );
    }
    final pages = selection.pagesToCreate().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PickerLabel('Dates', trailing: pages == 1 ? '1 page' : '$pages pages'),
        Wrap(
          spacing: Gaps.lg,
          runSpacing: Gaps.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Stepper(
              key: const ValueKey('planner-month'),
              label: PlannerDates.monthYear(plan.start),
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
        if (_style.period == PlannerPeriod.month)
          SwitchListTile(
            key: const ValueKey('planner-linked'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: plan.linked,
            onChanged: (v) => _setPlan(plan.copyWith(linked: v)),
            title: const Text('Add week and day pages'),
            subtitle: Text(
              'Tap a day or week on the calendar to jump to its page',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static DateTime _previous(PlannerPeriod period, DateTime d) => switch (period) {
    PlannerPeriod.day => PlannerDates.addDays(d, -1),
    PlannerPeriod.week => PlannerDates.addDays(d, -7),
    PlannerPeriod.month => PlannerDates.addMonths(d, -1),
  };
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
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
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
