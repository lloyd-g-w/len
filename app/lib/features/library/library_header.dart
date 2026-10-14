import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../settings/sync_alert_button.dart';
import 'library_actions.dart';
import 'library_breadcrumbs.dart';
import 'library_controller.dart';
import 'library_new_menu.dart';
import 'library_search_field.dart';
import 'library_view_menu.dart';

/// Title (or breadcrumbs) with a caption, and the tools beside it: search
/// (a 280-dp field when wide, a 🔍 that opens a field over the title when
/// narrow), ⊕▾ New (wide only), ⇅ View and, in the trash, Empty trash.
/// In a short window (a phone held sideways) the title is a heading and
/// the [folders] sit beside it, so the chrome is one row.
class LibraryHeader extends StatefulWidget {
  const LibraryHeader({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocus,
    required this.compact,
    this.short = false,
    this.folders,
    this.leading,
  });

  final LibraryActions actions;
  final TextEditingController searchController;
  final LibrarySearchFocus searchFocus;

  /// Phone layout: no ⊕▾ (the FAB creates), search behind 🔍.
  final bool compact;

  /// A short window: a smaller title, one row.
  final bool short;

  /// Beside the title, between it and the tools (short windows: the
  /// folders as a scroller); hidden while the search field is open.
  final Widget? folders;

  /// Before the title (phone: the drawer button).
  final Widget? leading;

  /// The widest the title takes beside [folders].
  static const double inlineTitleMaxWidth = 200;

  /// The narrowest header with a search field always shown.
  static const double searchFieldMinWidth = 560;

  @override
  State<LibraryHeader> createState() => _LibraryHeaderState();
}

class _LibraryHeaderState extends State<LibraryHeader> {
  /// Narrow layouts: the search field is open over the title.
  bool _searchOpen = false;

  LibraryActions get _actions => widget.actions;
  LibraryController get _c => _actions.controller;

  @override
  void initState() {
    super.initState();
    widget.searchFocus
      ..addListener(_onFocus)
      ..onOpen = _openSearch;
  }

  @override
  void didUpdateWidget(LibraryHeader old) {
    super.didUpdateWidget(old);
    if (old.searchFocus != widget.searchFocus) {
      old.searchFocus.removeListener(_onFocus);
      if (old.searchFocus.onOpen == _openSearch) old.searchFocus.onOpen = null;
      widget.searchFocus
        ..addListener(_onFocus)
        ..onOpen = _openSearch;
    }
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocus);
    if (widget.searchFocus.onOpen == _openSearch) widget.searchFocus.onOpen = null;
    super.dispose();
  }

  /// Ctrl+F (or a tap) focusing the field opens it; leaving it empty closes it.
  void _onFocus() {
    final open = widget.searchFocus.hasFocus || _c.isSearching;
    if (open != _searchOpen) setState(() => _searchOpen = open);
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    widget.searchFocus.requestFocus();
  }

  void _closeSearch() {
    widget.searchController.clear();
    _c.query = '';
    widget.searchFocus.unfocus();
    setState(() => _searchOpen = false);
  }

  String get _title => switch (_c.section) {
    LibrarySection.library => _c.folder?.name ?? 'Library',
    LibrarySection.favorites => 'Favourites',
    LibrarySection.trash => 'Trash',
  };

  String get _caption {
    final count = _c.visibleNotebooks.length;
    final folders = _c.visibleFolders.length;
    String plural(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    return switch (_c.section) {
      // The library also lists matches inside notebooks (features/search).
      LibrarySection.library when _c.isSearching => 'Titles and contents, across all folders',
      _ when _c.isSearching => '${plural(count, 'notebook')} across all folders',
      // One string at every width (short enough for a phone).
      LibrarySection.trash when count > 0 => '${plural(count, 'notebook')}, deleted after 30 days',
      // The empty state says it.
      _ when count == 0 && folders == 0 => '',
      _ => [
        if (folders > 0) plural(folders, 'folder'),
        if (count > 0 || folders == 0) plural(count, 'notebook'),
        // The order, when it isn't the usual one.
        if (count > 1)
          ?switch (_c.sort) {
            LibrarySort.edited => null,
            LibrarySort.created => 'by date created',
            LibrarySort.name => 'by name',
          },
      ].join(', '),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = _caption;
    // Nothing to search or sort while a view is empty (a search that found
    // nothing keeps its field).
    final empty = caption.isEmpty && !_c.isSearching;
    final inFolder = _c.section == LibrarySection.library && _c.folderId != null;
    // Phones: ← up a level inside folders (☰ reads as "at the top").
    final leading = inFolder && widget.compact
        ? IconButton(
            tooltip: 'Up to ${_c.folderById(_c.parentOf(_c.folder!))?.name ?? 'Library'}',
            icon: const Icon(Symbols.arrow_back_sharp),
            onPressed: _c.goUp,
          )
        : widget.leading;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: Motion.medium,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
          child: Semantics(
            key: ValueKey(_title),
            header: true,
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.short ? theme.textTheme.titleMedium : theme.textTheme.titleLarge,
            ),
          ),
        ),
        // No empty caption line: the title then centres on the ☰ and tools.
        if (caption.isNotEmpty) ...[
          const SizedBox(height: Gaps.xxs),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideSearch =
            !widget.compact && constraints.maxWidth >= LibraryHeader.searchFieldMinWidth;
        final search = LibrarySearchField(
          controller: widget.searchController,
          focus: widget.searchFocus,
          actions: _actions,
          onClose: wideSearch ? null : _closeSearch,
        );
        final searchOpen = !wideSearch && (_searchOpen || _c.isSearching);
        final folders = searchOpen ? null : widget.folders;
        final title = AnimatedSwitcher(
          duration: Motion.fast,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
          child: searchOpen
              ? KeyedSubtree(key: const ValueKey('search'), child: search)
              : KeyedSubtree(key: const ValueKey('title'), child: titleBlock),
        );
        final tools = <Widget>[
          // Phones: the sidebar's sync status is in the drawer.
          if (widget.compact && !searchOpen) SyncAlertButton(sync: _c.services.sync),
          if (empty)
            const SizedBox.shrink()
          else if (wideSearch) ...[
            SizedBox(width: 280, child: search),
            const SizedBox(width: Gaps.sm),
          ] else if (!searchOpen)
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Symbols.search_sharp),
              onPressed: _openSearch,
            ),
          if (!widget.compact && _c.section == LibrarySection.library)
            LibraryNewMenu(actions: _actions),
          if (!empty) LibraryViewMenu(actions: _actions),
          if (_c.section == LibrarySection.trash && _c.trash.isNotEmpty)
            _emptyTrash(theme, wideSearch),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Phones go up with ← instead.
            if (inFolder && !widget.compact && !searchOpen) ...[
              LibraryBreadcrumbs(actions: _actions),
              const SizedBox(height: Gaps.xxs),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.short ? Targets.touch : 52),
              child: Row(
                children: [
                  if (leading case final leading? when !searchOpen) ...[
                    leading,
                    const SizedBox(width: Gaps.xs),
                  ],
                  if (folders == null)
                    Expanded(child: title)
                  else ...[
                    // The title as wide as it needs (up to a limit), the
                    // folders in the rest, a hairline between (DESIGN §3).
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: LibraryHeader.inlineTitleMaxWidth,
                      ),
                      child: title,
                    ),
                    const SizedBox(width: Gaps.md),
                    SizedBox(
                      height: Gaps.xl,
                      child: VerticalDivider(
                        width: Hairline.width,
                        thickness: Hairline.width,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    const SizedBox(width: Gaps.xs),
                    Expanded(child: folders),
                  ],
                  const SizedBox(width: Gaps.md),
                  ...tools,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyTrash(ThemeData theme, bool wide) {
    void empty() => unawaited(_actions.emptyTrash(context));
    if (!wide) {
      return IconButton(
        tooltip: 'Empty trash…',
        color: theme.colorScheme.error,
        icon: const Icon(Symbols.delete_sweep_sharp),
        onPressed: empty,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: Gaps.xs),
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        onPressed: empty,
        icon: const Icon(Symbols.delete_sweep_sharp, size: Glyphs.menu),
        label: const Text('Empty trash…'),
      ),
    );
  }
}
