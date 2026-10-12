import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/paper.dart';
import '../../ink/ink_surface.dart';
import '../../ink/lab/input_recording.dart';
import '../../ui/messages.dart';
import 'inklab_files.dart';
import 'inklab_pen_menu.dart';
import 'inklab_replay.dart';
import 'inklab_session.dart';
import 'inklab_stats_bar.dart';
import 'perf_notebooks.dart';

/// The hidden developer screen for measuring and recording handwriting
/// input: a scratch surface on the real drawing pipeline, live statistics,
/// and `.leninput` recordings that can be saved, opened and replayed in
/// real time (see `docs/INK_LAB.md`). Nothing drawn here is persisted.
class InkLabScreen extends StatefulWidget {
  const InkLabScreen({super.key, this.stylusOnly = false});

  /// Palm rejection: fingers navigate, only the stylus draws.
  final bool stylusOnly;

  @override
  State<InkLabScreen> createState() => _InkLabScreenState();
}

class _InkLabScreenState extends State<InkLabScreen> with TickerProviderStateMixin {
  InkLabSession? _session;
  InkLabReplay? _replay;

  /// The recording opened last, or replayed last (replayed again by
  /// Replay when nothing new was drawn).
  InputRecording? _loaded;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    InkLabSession.open(stylusOnly: widget.stylusOnly).then((s) {
      if (_disposed) {
        s.dispose();
      } else {
        setState(() => _session = s..startRecording());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _replay?.dispose();
    _session?.dispose();
    super.dispose();
  }

  bool get _replaying => _replay?.running ?? false;

  void _record(PointerEvent e) {
    final session = _session;
    if (session != null && session.recording) session.recorder.addPointer(e);
  }

  void _clear() {
    _stopReplay();
    _loaded = null;
    _session?.clear();
  }

  void _stopReplay() {
    _replay
      ?..stop()
      ..dispose();
    setState(() => _replay = null);
  }

  void _replayRecording(InputRecording recording) {
    final session = _session!;
    _stopReplay();
    _loaded = recording;
    final replay = InkLabReplay(session, recording, vsync: this, pen: session.pen);
    replay.onDone = () {
      if (!mounted) return;
      setState(() {});
      _message('Replayed ${session.strokeCount} strokes');
    };
    setState(() => _replay = replay..start());
  }

  void _replayLatest() {
    final session = _session!;
    final recording = session.recorder.isEmpty ? _loaded : session.recordingSoFar;
    if (recording == null) return _message('Nothing to replay: write something or open a file');
    _replayRecording(recording);
  }

  Future<void> _open() async {
    final recording = await openRecording(context);
    if (recording == null || !mounted || _session == null) return;
    _session!.pen = recording.meta.pen;
    _replayRecording(recording);
  }

  Future<void> _save() async {
    final session = _session!;
    if (session.recorder.isEmpty) return _message('Nothing recorded yet');
    await saveRecording(context, session.recordingSoFar);
  }

  void _message(String text) => showMessage(context, text);

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ink Lab'),
        actions: session == null ? null : _actions(session),
      ),
      body: session == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _surface(session)),
                InkLabStatsBar(session: session, replaying: _replaying),
              ],
            ),
    );
  }

  List<Widget> _actions(InkLabSession session) => [
    ListenableBuilder(
      listenable: session,
      builder: (context, _) => InkLabPenMenu(pen: session.pen, onChanged: (p) => session.pen = p),
    ),
    IconButton(tooltip: 'Clear', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
    IconButton(
      tooltip: _replaying ? 'Stop replay' : 'Replay',
      icon: Icon(_replaying ? Icons.stop_rounded : Icons.replay_rounded),
      onPressed: _replaying ? _stopReplay : _replayLatest,
    ),
    IconButton(
      tooltip: 'Open recording',
      icon: const Icon(Icons.file_open_outlined),
      onPressed: _open,
    ),
    IconButton(
      tooltip: 'Save recording',
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: _replaying ? null : _save,
    ),
    PopupMenuButton<bool>(
      tooltip: 'Perf test notebooks',
      icon: const Icon(Icons.speed_rounded),
      onSelected: _perfNotebooks,
      itemBuilder: (context) => const [
        PopupMenuItem(value: true, child: Text('Create perf test notebooks')),
        PopupMenuItem(value: false, child: Text('Delete perf test notebooks')),
      ],
    ),
  ];

  /// Creates or deletes the "Perf test …" scratch notebooks.
  void _perfNotebooks(bool create) {
    final services = AppScope.of(context);
    if (create) {
      final strokes = PerfNotebooks.create(services);
      _message('Created perf test notebooks ($strokes strokes)');
    } else {
      _message('Deleted ${PerfNotebooks.deleteAll(services)} perf test notebooks');
    }
  }

  /// The surface, wrapped in a `Listener` of exactly its size that records
  /// every pointer event without taking part in hit testing.
  Widget _surface(InkLabSession session) {
    session.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        session.viewSize = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _record,
          onPointerMove: _record,
          onPointerUp: _record,
          onPointerCancel: _record,
          onPointerHover: _record,
          child: IgnorePointer(
            ignoring: _replaying,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => InkSurface(
                model: session.model,
                viewport: session.viewport,
                input: session.input,
                live: session.live,
                paper: PaperStyle.blank,
              ),
            ),
          ),
        );
      },
    );
  }
}
