import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../ui/app_theme.dart';
import '../../ui/sidebar_item.dart';
import 'about_settings.dart';
import 'appearance_settings.dart';
import 'editor_settings.dart';
import 'handwriting_settings.dart';
import 'input_settings.dart';
import 'sync_settings.dart';

/// One settings section: its name and icon in the two-pane list, and its card.
typedef _Page = ({String title, IconData icon, WidgetBuilder build});

/// Settings: appearance, stylus, gestures, editor, handwriting, sync and about.
///
/// Narrow windows show the sections as grouped cards in one readable column;
/// from [Breakpoints.expanded] a list of sections on the left picks the one
/// shown on the right (GoodNotes on iPad).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The section shown in the two-pane layout.
  int _selected = 0;

  /// The sections, in order. Icons match the sections' own headers.
  List<_Page> _pages(BuildContext context) {
    final services = AppScope.of(context);
    final preferences = services.preferences;
    return [
      (
        title: 'Appearance',
        icon: Icons.palette_outlined,
        build: (_) => AppearanceSettings(preferences: preferences),
      ),
      (
        title: 'Stylus',
        icon: Icons.edit_outlined,
        build: (_) => StylusSettings(preferences: preferences),
      ),
      (
        title: 'Gestures',
        icon: Icons.touch_app_outlined,
        build: (_) => GestureSettings(preferences: preferences),
      ),
      (
        title: 'Editor',
        icon: Icons.space_dashboard_outlined,
        build: (_) => EditorSettings(preferences: preferences),
      ),
      (
        title: 'Handwriting',
        icon: Icons.draw_outlined,
        build: (_) => HandwritingSettings(recognition: services.recognition),
      ),
      (title: 'Sync', icon: Icons.cloud_outlined, build: (_) => const SyncSettings()),
      (title: 'About', icon: Icons.info_outline_rounded, build: (_) => const AboutSettings()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pages = _pages(context);
    final compact = width < Breakpoints.medium;
    // Phones: the title lives in a pinned bar, so the bar is never empty.
    return Scaffold(
      appBar: compact ? null : AppBar(scrolledUnderElevation: 0.5),
      body: width >= Breakpoints.expanded
          ? _twoPane(context, pages)
          : _column(context, pages, compact: compact),
    );
  }

  Widget _heading(BuildContext context, {required bool compact}) => Padding(
    padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, 0, Gaps.xl),
    child: Text(
      'Settings',
      style: compact
          ? Theme.of(context).textTheme.headlineMedium
          : Theme.of(context).textTheme.headlineLarge,
    ),
  );

  /// Every section as a card, in a column of readable width.
  Widget _column(BuildContext context, List<_Page> pages, {required bool compact}) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? Gaps.lg : Gaps.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) _heading(context, compact: false),
              for (final page in pages) page.build(context),
            ],
          ),
        ),
      ),
    );
    final bottom = Gaps.xxl + MediaQuery.paddingOf(context).bottom;
    if (!compact) {
      return ListView(
        padding: EdgeInsets.only(bottom: bottom),
        children: [content],
      );
    }
    return CustomScrollView(
      slivers: [
        const SliverAppBar(pinned: true, title: Text('Settings'), scrolledUnderElevation: 0.5),
        SliverPadding(
          padding: EdgeInsets.only(bottom: bottom),
          sliver: SliverToBoxAdapter(child: content),
        ),
      ],
    );
  }

  /// Section list on the left, the selected section on the right.
  Widget _twoPane(BuildContext context, List<_Page> pages) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.clamp(0, pages.length - 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 280,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: scheme.outlineVariant)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.xl),
            children: [
              _heading(context, compact: false),
              for (var i = 0; i < pages.length; i++)
                Semantics(
                  selected: i == selected,
                  child: SidebarItem(
                    icon: pages[i].icon,
                    label: pages[i].title,
                    selected: i == selected,
                    onTap: () => setState(() => _selected = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.fast,
            child: ListView(
              // A fresh scroll position per section.
              key: ValueKey(selected),
              padding: EdgeInsets.fromLTRB(
                Gaps.xxl,
                Gaps.xs,
                Gaps.xxl,
                Gaps.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    // Readable line length on wide desktop windows.
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: pages[selected].build(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
