import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../platform/browser_storage.dart';
import '../../ui/app_theme.dart';
import 'about_settings.dart';
import 'appearance_settings.dart';
import 'editor_settings.dart';
import 'handwriting_settings.dart';
import 'input_settings.dart';
import 'storage_settings.dart';
import 'sync_settings.dart';

/// Settings: appearance, stylus, gestures, editor, handwriting, sync, storage
/// (web only) and about, as grouped cards in one readable, centred column.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// The sections, in order.
  List<Widget> _sections(BuildContext context) {
    final services = AppScope.of(context);
    final preferences = services.preferences;
    return [
      AppearanceSettings(preferences: preferences),
      StylusSettings(preferences: preferences),
      GestureSettings(preferences: preferences),
      EditorSettings(preferences: preferences),
      HandwritingSettings(recognition: services.recognition),
      const SyncSettings(),
      if (browserStorage case final storage?) StorageSettings(storage: storage),
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
    child: Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
  );

  /// Every section as a card, in a column of readable width.
  Widget _column(BuildContext context, List<Widget> sections, {required bool compact}) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
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
