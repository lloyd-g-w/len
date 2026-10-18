import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../platform/browser_storage.dart';
import '../../ui/app_theme.dart';
import '../../ui/escape_closes.dart';
import 'about_settings.dart';
import 'backup_settings.dart';
import 'general_settings.dart';
import 'handwriting_settings.dart';
import 'keyboard_shortcuts.dart';
import 'settings_section.dart';
import 'storage_settings.dart';
import 'sync_settings.dart';
import 'writing_settings.dart';

/// Settings (DESIGN §6.4): General, Writing, Handwriting, Sync, Backup,
/// Storage and About, as open ruled lists in one centred column at most
/// [maxWidth] wide; on wide screens the headings hang in its margin column.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.showSync = false});

  /// Scrolls to Sync once shown (opened from a failed sync status).
  final bool showSync;

  /// The column's widest (the headings' margin column and the rows).
  static const double maxWidth = 800;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    // "Also Ctrl+/ anywhere" (General → Keyboard shortcuts), here too.
    bindings: keyboardShortcutsBinding(() => unawaited(showKeyboardShortcuts(context))),
    child: EscapeCloses(
      child: Scaffold(body: _SettingsColumn(showSync: showSync)),
    ),
  );
}

/// The sections under a pinned bar titled "Settings"; the bar gets its
/// hairline once the column scrolls under it.
class _SettingsColumn extends StatefulWidget {
  const _SettingsColumn({required this.showSync});

  final bool showSync;

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
    // The margin column (DESIGN §3); rows overhang it by their plate's edge.
    final gutter = compact ? Gaps.lg : Gaps.xl;
    const overhang = SettingsTile.edge;
    // The title lines up with the (centred) column's margin below it.
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
          padding: EdgeInsets.symmetric(horizontal: gutter - overhang),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _sections(context, showSync: widget.showSync),
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
List<Widget> _sections(BuildContext context, {required bool showSync}) {
  final services = AppScope.of(context);
  final preferences = services.preferences;
  return [
    GeneralSettings(preferences: preferences),
    WritingSettings(preferences: preferences),
    HandwritingSettings(recognition: services.recognition),
    SyncSettings(reveal: showSync),
    const BackupSettings(),
    StorageSettings(
      overview: services.storage,
      storage: browserStorage,
      filesKept: services.blobsArePersistent,
      writes: services.writes,
    ),
    const AboutSettings(),
  ];
}
