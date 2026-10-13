import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../platform/browser_storage.dart';
import '../../ui/app_theme.dart';
import 'about_settings.dart';
import 'general_settings.dart';
import 'handwriting_settings.dart';
import 'storage_settings.dart';
import 'sync_settings.dart';
import 'writing_settings.dart';

/// Settings (REDESIGN §4): General, Writing, Handwriting, Sync, Storage
/// (web only) and About, in one centred column at most [maxWidth] wide.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// The column's widest.
  static const double maxWidth = 640;

  @override
  Widget build(BuildContext context) => const Scaffold(body: _SettingsColumn());
}

/// The sections under a pinned bar titled "Settings"; the bar gets its
/// hairline once the column scrolls under it.
class _SettingsColumn extends StatefulWidget {
  const _SettingsColumn();

  @override
  State<_SettingsColumn> createState() => _SettingsColumnState();
}

class _SettingsColumnState extends State<_SettingsColumn> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final scrolled = n.metrics.pixels > 0;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.medium;
    final gutter = compact ? Gaps.lg : Gaps.xl;
    // The title lines up with the (centred) column below it.
    final columnStart = (width - SettingsScreen.maxWidth).clamp(0.0, double.infinity) / 2 + gutter;
    final hasBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final titleSpacing = (columnStart - (hasBack ? kToolbarHeight : 0)).clamp(
      NavigationToolbar.kMiddleSpacing,
      double.infinity,
    );
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SettingsScreen.maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _sections(context),
          ),
        ),
      ),
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Settings'),
            titleSpacing: titleSpacing,
            shape: _scrolled ? Border(bottom: Surfaces.chromeEdge(scheme)) : null,
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: Gaps.xxl + MediaQuery.paddingOf(context).bottom),
            sliver: SliverToBoxAdapter(child: content),
          ),
        ],
      ),
    );
  }
}

/// The settings sections, in order.
List<Widget> _sections(BuildContext context) {
  final services = AppScope.of(context);
  final preferences = services.preferences;
  return [
    GeneralSettings(preferences: preferences),
    WritingSettings(preferences: preferences),
    HandwritingSettings(recognition: services.recognition),
    const SyncSettings(),
    if (browserStorage case final storage?) StorageSettings(storage: storage),
    const AboutSettings(),
  ];
}
