import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../domain/paper.dart';
import '../../../domain/templates/user_template.dart';
import '../../../ui/app_theme.dart';
import 'template_catalog.dart';
import 'template_gallery.dart';
import 'template_options.dart';
import 'user_templates.dart';

/// Everything about the paper of new or existing pages, shared by the
/// template picker and the new-notebook sheet: search and category
/// filters, the gallery (with My templates), planner dates, paper colour
/// and page size — stacked (scrolled by the parent), or [split]: the
/// gallery left and the options (with a preview) in a column on the
/// right, each scrolling on its own so the options stay in view.
class TemplateChooser extends StatefulWidget {
  const TemplateChooser({
    super.key,
    required this.selection,
    required this.onChanged,
    this.canvas = false,
    this.sizeEditable = true,
    this.generate = true,
    this.tileWidth = 80,
    this.split = false,
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

  /// Side-by-side layout (needs a bounded height).
  final bool split;

  /// Width of the options column in the [split] layout.
  static const double optionsWidth = 300;

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
      // Bring the dates into view (they appear below the gallery or at
      // the top of the options column).
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
        // A search looks through every category.
        only: _query.text.trim().isEmpty ? _category : null,
        mine: _mine,
      ))
        // Without the app's services (standalone use) there is no My templates.
        if (_services != null || section.$1 != TemplateCategory.mine) section,
    ];
    final gallery = <Widget>[
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
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    ];
    final options = TemplateOptions(
      selection: _s,
      onChanged: widget.onChanged,
      canvas: widget.canvas,
      sizeEditable: widget.sizeEditable,
      generate: widget.generate,
      preview: widget.split,
      plannerKey: _optionsKey,
    );
    if (!widget.split) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...gallery, options],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.lg, Gaps.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gallery),
          ),
        ),
        VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
        SizedBox(
          width: TemplateChooser.optionsWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.lg, Gaps.xl, Gaps.lg),
            child: options,
          ),
        ),
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
      prefixIcon: const Icon(Symbols.search_rounded, size: 20),
      suffixIcon: _query.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Symbols.close_rounded, size: 18),
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
      // Chips scroll out to the sheet edge rather than being cut at the inset.
      clipBehavior: Clip.none,
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
