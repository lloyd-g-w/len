import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';
import '../../../ui/app_theme.dart';
import 'page_setup.dart';
import 'planner_options.dart';
import 'template_catalog.dart';
import 'template_gallery.dart';
import 'user_templates.dart';

/// Everything about the paper of new or existing pages, shared by the
/// template picker and the new-notebook sheet: search and category
/// filters, the gallery (with My templates), planner dates, paper colour
/// and page size.
class TemplateChooser extends StatefulWidget {
  const TemplateChooser({
    super.key,
    required this.selection,
    required this.onChanged,
    this.canvas = false,
    this.sizeEditable = true,
    this.generate = true,
    this.tileWidth = 80,
  });

  final TemplateSelection selection;
  final ValueChanged<TemplateSelection> onChanged;

  /// Choosing a canvas background: tiling templates, no size.
  final bool canvas;

  /// Whether page size and orientation can be chosen.
  final bool sizeEditable;

  /// Whether planners generate a range of pages (else one date).
  final bool generate;
  final double tileWidth;

  @override
  State<TemplateChooser> createState() => _TemplateChooserState();
}

class _TemplateChooserState extends State<TemplateChooser> {
  final _query = TextEditingController();
  final _optionsKey = GlobalKey();
  TemplateCategory? _category;
  List<UserTemplate> _mine = const [];
  AppServices? _services;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.maybeRead(context);
    _loadMine();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _loadMine() => _mine = _services?.templates.list() ?? const [];

  TemplateSelection get _s => widget.selection;

  void _select(TemplateEntry entry) {
    final wasPlanner = _s.style.isPlanner;
    widget.onChanged(_s.select(entry));
    if (!wasPlanner && entry is BuiltInTemplate && entry.style.isPlanner) {
      // Bring the dates into view (they appear below the gallery).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final options = _optionsKey.currentContext;
        if (options != null && options.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              options,
              duration: Motion.medium,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ),
          );
        }
      });
    }
  }

  Future<void> _import() async {
    final template = await UserTemplates.import(context);
    if (template == null || !mounted) return;
    setState(_loadMine);
    _select(MyTemplate(template));
  }

  Future<void> _menu(UserTemplate template, Offset at) async {
    final changed = await UserTemplates.showMenu(context, template, at: at);
    if (changed && mounted) setState(_loadMine);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = [
      for (final section in templateSections(
        canvas: widget.canvas,
        query: _query.text,
        only: _category,
        mine: _mine,
      ))
        // Without the app's services (standalone use) there is no My templates.
        if (_services != null || section.$1 != TemplateCategory.mine) section,
    ];
    final custom = _s.template.customSize != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(theme),
        const SizedBox(height: Gaps.sm),
        _categoryChips(),
        const SizedBox(height: Gaps.lg),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gaps.xl),
            child: Text(
              'No templates match “${_query.text.trim()}”',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          TemplateGallery(
            sections: sections,
            selection: widget.canvas
                ? _s.copyWith(template: _s.template.copyWith(orientation: PageOrientation.portrait))
                : _s,
            tileWidth: widget.tileWidth,
            onSelect: _select,
            onImport: _services == null || widget.canvas ? null : _import,
            onTemplateMenu: _services == null ? null : _menu,
          ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: _s.style.isPlanner && !widget.canvas
              ? Padding(
                  key: _optionsKey,
                  padding: const EdgeInsets.only(top: Gaps.lg),
                  child: PlannerOptions(
                    selection: _s,
                    generate: widget.generate,
                    onChanged: widget.onChanged,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: Gaps.lg),
        PickerLabel(widget.canvas ? 'Background colour' : 'Paper colour'),
        PaperColorRow(
          template: _s.template,
          onChanged: (t) => widget.onChanged(_s.copyWith(template: t)),
        ),
        if (widget.sizeEditable && !widget.canvas) ...[
          const SizedBox(height: Gaps.lg),
          PickerLabel('Page size', trailing: custom ? 'Set by the template' : null),
          IgnorePointer(
            ignoring: custom,
            child: Opacity(
              opacity: custom ? 0.45 : 1,
              child: PageSizeRow(
                template: _s.template,
                onChanged: (t) => widget.onChanged(_s.copyWith(template: t)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _searchField(ThemeData theme) => TextField(
    key: const ValueKey('template-search'),
    controller: _query,
    onChanged: (_) => setState(() {}),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Search templates',
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      suffixIcon: _query.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(_query.clear),
            ),
    ),
  );

  Widget _categoryChips() {
    final categories = [
      null,
      for (final c in TemplateCategory.values)
        if (_offered(c)) c,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: Gaps.sm),
              child: ChoiceChip(
                key: ValueKey('category-${c?.name ?? 'all'}'),
                showCheckmark: false,
                label: Text(c?.label ?? 'All'),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
            ),
        ],
      ),
    );
  }

  bool _offered(TemplateCategory c) => switch (c) {
    TemplateCategory.mine => !widget.canvas && _services != null,
    TemplateCategory.planners => !widget.canvas,
    _ => true,
  };
}
