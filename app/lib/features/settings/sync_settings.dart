import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../sync/server_only_files.dart';
import '../../sync/sync_api.dart';
import '../../sync/sync_controller.dart';
import '../../sync/sync_setup_link.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import '../documents/progress_dialog.dart';
import 'name_tags_tile.dart';
import 'settings_section.dart';
import 'sync_setup_dialog.dart';
import 'sync_status_line.dart';

part 'sync_settings_views.dart';

/// Sync: once connected the server, its status, Sync now, Change…, Set up
/// another device… and Turn off sync…, then the Name tags switch; otherwise
/// (or while changing) the URL and token form, with a connection test. A
/// setup link fills the form: pasted into the URL field, or opened with Len
/// ([IncomingFiles.syncSetup]).
class SyncSettings extends StatefulWidget {
  const SyncSettings({super.key, this.reveal = false});

  /// What a Len sync server is and how to run one.
  static final Uri serverGuide = Uri.parse(
    'https://github.com/lloyd-g-w/len/blob/main/server/README.md',
  );

  /// Scrolls itself into view once shown (Settings opened from a failed
  /// sync status).
  final bool reveal;

  /// [url] as typed, completed: trimmed, and `https://` assumed when no
  /// scheme is given ("len.example" → "https://len.example").
  static String completeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.contains('://')) return trimmed;
    return 'https://$trimmed';
  }

  /// Null if [url] is a usable http(s) URL; otherwise a message explaining
  /// what is wrong.
  static String? validateUrl(String url) {
    if (url.isEmpty) return 'Enter the address of your Len server';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return 'Enter a web address, e.g. len.example.com or http://192.168.1.10:8080';
    }
    return null;
  }

  @override
  State<SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends State<SyncSettings> {
  late final AppServices _services = AppScope.read(context);
  late final _url = TextEditingController(text: _services.settings.syncUrl);
  late final _token = TextEditingController(text: _sync.tokens.token);
  bool _obscureToken = true;
  bool _busy = false;

  /// Bumped by each connection test and by Cancel: a test whose answer
  /// arrives after either is ignored.
  int _attempt = 0;

  /// The form is shown although sync is set up (Change…).
  bool _editing = false;

  /// The last connection test's failure, under the form.
  String? _testError;

  /// Shown under the URL field until it is edited.
  String? _urlError;

  /// Shown under the token field until it is edited: none typed, or the
  /// server turned it away (UX_AUDIT R14-7).
  String? _tokenError;

  /// The form was filled from a setup link: its caption says where links
  /// come from, for next time.
  bool _fromLink = false;

  SyncController get _sync => _services.sync;

  /// Said once: the secure store failed, so the token is in the database.
  static const _tokenNoteTip = 'sync_token_in_database';
  late final bool _tokenNote =
      _sync.tokens.inDatabase && !_services.settings.seenTips.contains(_tokenNoteTip);

  ValueNotifier<SyncSetupLink?> get _incoming => _services.incomingFiles.syncSetup;

  @override
  void initState() {
    super.initState();
    if (_tokenNote) _services.settings.markTipSeen(_tokenNoteTip);
    _incoming.addListener(_takeIncoming);
    _takeIncoming();
    if (!widget.reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: Motion.moving(context, Motion.travel),
          curve: Motion.move,
        ),
      );
    });
  }

  @override
  void dispose() {
    _incoming.removeListener(_takeIncoming);
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  /// Fills the form from a setup link opened with Len (and takes it).
  void _takeIncoming() {
    final link = _incoming.value;
    if (link == null) return;
    _incoming.value = null;
    _fill(link);
    if (mounted) setState(() {});
  }

  /// Fills both fields from [link] (the form opens if sync is set up); the
  /// user still connects.
  void _fill(SyncSetupLink link) {
    _url.text = link.url;
    _token.text = link.token;
    _editing = _sync.isConfigured;
    _fromLink = true;
    _testError = _urlError = _tokenError = null;
  }

  /// A setup link pasted into the URL field fills both fields.
  void _onUrlChanged(String text) {
    if (SyncSetupLink.parse(text) case final link?) return setState(() => _fill(link));
    if (_urlError != null) setState(() => _urlError = null);
  }

  void _onTokenChanged(String _) {
    if (_tokenError != null) setState(() => _tokenError = null);
  }

  Future<void> _testAndSave() async {
    final url = SyncSettings.completeUrl(_url.text);
    // Show what is used ("https://" added).
    if (url != _url.text) _url.text = url;
    final urlError = SyncSettings.validateUrl(url);
    if (urlError != null) {
      setState(() {
        _urlError = urlError;
        _testError = _tokenError = null;
      });
      return;
    }
    // What was tested is what gets saved: the fields may change (or Cancel
    // may restore them) while the server answers.
    final token = _token.text.trim();
    if (token.isEmpty) {
      return setState(() {
        _tokenError = 'Enter the access token';
        _testError = null;
      });
    }
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _testError = _tokenError = null;
    });
    try {
      final info = await _sync.test(url: url, token: token);
      if (attempt != _attempt || !mounted) return;
      // Another server: files only the one left holds come here first.
      final previous = _services.settings.syncServerId;
      if (_sync.isConfigured && previous.isNotEmpty && info.serverId != previous) {
        if (!await _keepServerOnlyFiles(goOn: 'Switch anyway')) return;
        if (attempt != _attempt || !mounted) return;
      }
      _sync.configure(url: url, token: token);
      _editing = _fromLink = false;
      unawaited(_sync.syncNow());
    } on SyncException catch (e) {
      if (attempt != _attempt) return;
      // A wrong token is said on its field; the rest under the form.
      if (e.kind == SyncFailure.auth) {
        _tokenError = e.message;
      } else {
        _testError = e.message;
      }
    } on ArgumentError {
      // e.g. the http client rejecting a malformed URI.
      if (attempt == _attempt) _urlError = 'This address isn’t valid';
    } finally {
      if (mounted && attempt == _attempt) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final serverOnly = ServerOnlyFiles(_sync).find().isNotEmpty;
    final confirmed = await confirmAction(
      context,
      title: 'Turn off sync?',
      message: serverOnly
          ? 'Your notebooks stay on this device and on the server. Some of their files are '
                'only on the server now: they are downloaded first. This device stops syncing '
                'until you connect it again.'
          : 'Your notebooks stay on this device and on the server. This device stops '
                'syncing until you connect it again.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed || !mounted) return;
    if (!await _keepServerOnlyFiles(goOn: 'Turn off anyway') || !mounted) return;
    _sync.configure(url: '', token: '');
    setState(() {
      _url.clear();
      _token.clear();
      _editing = false;
      _testError = null;
    });
  }

  /// Downloads the files only the server holds before this device leaves
  /// it ([ServerOnlyFiles]); those that can't be are out of reach after,
  /// so the user is asked whether to [goOn]. Whether to.
  Future<bool> _keepServerOnlyFiles({required String goOn}) async {
    final files = ServerOnlyFiles(_sync);
    final shas = files.find();
    if (shas.isEmpty) return true;
    final int failed;
    try {
      failed = await runWithSteps(
        context,
        'Downloading files',
        (progress) => files.download(
          shas,
          check: progress.check,
          onProgress: (done, total) => progress.step(done, total, unit: 'file'),
        ),
        cancellable: true,
      );
    } on Cancelled {
      return false;
    }
    if (failed == 0) return true;
    if (!mounted) return false;
    return confirmAction(
      context,
      title: 'Some files couldn’t be downloaded',
      message: failed == 1
          ? 'One file your notebooks show couldn’t be downloaded from the server. Without '
                'the server, it shows as missing on this device.'
          : '$failed files your notebooks show couldn’t be downloaded from the server. '
                'Without the server, they show as missing on this device.',
      confirmLabel: goOn,
    );
  }

  /// Cancel (also while a test runs: its answer is then ignored).
  void _cancelEditing() => setState(() {
    _attempt++;
    _busy = false;
    _url.text = _services.settings.syncUrl;
    _token.text = _sync.tokens.token;
    _editing = _fromLink = false;
    _testError = _urlError = _tokenError = null;
  });

  /// Change…: shows the form although sync is set up.
  void _startEditing() => setState(() => _editing = true);

  void _toggleObscureToken() => setState(() => _obscureToken = !_obscureToken);

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Sync',
      description: 'Sync across your devices through your own Len server',
      children: [
        ListenableBuilder(
          listenable: _sync,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: SettingsTile.edge, vertical: Gaps.md),
            child: _sync.isConfigured && !_editing ? _connected(context) : _form(context),
          ),
        ),
        // Live sync shows other devices' pointers once connected.
        ListenableBuilder(
          listenable: _sync,
          builder: (context, _) => _sync.isConfigured && !_editing
              ? NameTagsTile(preferences: _services.preferences)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
