import 'dart:async';

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
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showSync = false});

  /// Scrolls to Sync once shown (opened from a failed sync status).
  final bool showSync;

  /// The column's widest.
  static const double maxWidth = 640;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _syncKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!widget.showSync) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sync = _syncKey.currentContext;
      if (sync == null || !sync.mounted) return;
      unawaited(Scrollable.ensureVisible(sync, duration: Motion.travel, curve: Motion.move));
    });
  }

  /// The sections, in order.
  List<Widget> _sections(BuildContext context) {
    final services = AppScope.of(context);
    final preferences = services.preferences;
    return [
      GeneralSettings(preferences: preferences),
      WritingSettings(preferences: preferences),
      HandwritingSettings(recognition: services.recognition),
      SyncSettings(key: _syncKey),
      if (browserStorage case final storage?)
        StorageSettings(storage: storage, filesKept: services.blobsArePersistent),
      const AboutSettings(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    // Phones: the title lives in a pinned bar, so the bar is never empty.
    return Scaffold(
      appBar: compact ? null : AppBar(scrolledUnderElevation: 0.5),
      body: _column(context, _sections(context), compact: compact),
    );
  }

  Widget _heading(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, 0, Gaps.xl),
    child: Text('Settings', style: Theme.of(context).textTheme.titleLarge),
  );

  /// Every section as a card, in a column of readable width.
  Widget _column(BuildContext context, List<Widget> sections, {required bool compact}) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SettingsScreen.maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? Gaps.lg : Gaps.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [if (!compact) _heading(context), ...sections],
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
}
