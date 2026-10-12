import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/pointer_activity.dart';
import '../../data/app_database.dart';
import '../../data/search/ink_text_schema.dart';
import '../../data/settings_repository.dart';
import '../../domain/stroke.dart';
import 'handwriting_indexer.dart';
import 'handwriting_recognizer.dart';
import 'recognition_languages.dart';

/// Handwriting recognition for the app: the platform's recogniser, the
/// chosen language (from the device locale unless set), its model
/// (download / delete) and the background [indexer] for search.
///
/// When indexing is on and the model is missing, [start] downloads it over
/// Wi-Fi; the settings and "Convert to text" offer to download it on
/// demand.
class RecognitionService extends ChangeNotifier {
  RecognitionService({
    required this.recognizer,
    required this.settings,
    required AppDatabase database,
    List<Locale> Function()? deviceLocales,
    Duration idleDelay = const Duration(seconds: 3),
    PointerActivity? activity,
  }) : _database = database,
       _deviceLocales = deviceLocales ?? (() => PlatformDispatcher.instance.locales) {
    indexer = HandwritingIndexer(
      database,
      recognizer: recognizer,
      language: () => language,
      idleDelay: idleDelay,
      activity: activity,
    );
  }

  final HandwritingRecognizer recognizer;
  final SettingsRepository settings;
  final AppDatabase _database;
  final List<Locale> Function() _deviceLocales;

  /// Recognises queued surfaces in the background (see [HandwritingIndexer]).
  late final HandwritingIndexer indexer;

  ModelStatus _model = ModelStatus.unknown;
  Object? _downloadError;
  bool _disposed = false;

  /// Approximate size of one language model, for the UI.
  static const String modelSize = '~20 MB';

  bool get isSupported => recognizer.isSupported;
  String get unsupportedReason => recognizer.unsupportedReason;

  /// The recognition language (BCP 47).
  String get language => settings.handwritingLanguage ?? automaticLanguage;

  /// The language picked from the device's locales.
  String get automaticLanguage => RecognitionLanguages.forLocales(_deviceLocales());

  /// Whether [language] follows the device locale.
  bool get isAutomaticLanguage => settings.handwritingLanguage == null;

  /// Sets the language ([tag] null: follow the device). Everything is
  /// recognised again in the new language once its model is on the device.
  Future<void> setLanguage(String? tag) async {
    final before = language;
    settings.handwritingLanguage = tag;
    if (language == before) {
      notifyListeners();
      return;
    }
    _database.transaction(() => InkTextSchema.queueAll(_database.db));
    _model = ModelStatus.unknown;
    _downloadError = null;
    notifyListeners();
    await _prepare();
  }

  /// Whether handwriting is recognised in the background for search.
  bool get indexingEnabled => settings.handwritingIndexing;

  /// Switching indexing off forgets the recognised text; switching it on
  /// recognises everything again.
  Future<void> setIndexingEnabled(bool value) async {
    if (value == indexingEnabled) return;
    settings.handwritingIndexing = value;
    if (value) {
      _database.transaction(() => InkTextSchema.queueAll(_database.db));
    } else {
      indexer.stop();
      indexer.clear();
    }
    notifyListeners();
    await _prepare();
  }

  /// State of [language]'s model.
  ModelStatus get modelStatus => _model;

  /// Why the last download failed, if it did.
  Object? get downloadError => _downloadError;

  /// Checks the model and starts indexing (downloading the model over
  /// Wi-Fi first if indexing is on). Call once at startup.
  Future<void> start() => _prepare(autoDownload: true);

  Future<void> _prepare({bool autoDownload = false}) async {
    if (!isSupported || _disposed) return;
    await refreshModel();
    if (autoDownload && indexingEnabled && _model == ModelStatus.missing) {
      unawaited(download(wifiOnly: true));
    }
    _updateIndexer();
  }

  /// Re-checks whether [language]'s model is downloaded.
  Future<void> refreshModel() async {
    if (!isSupported || _model == ModelStatus.downloading) return;
    final lang = language;
    final bool downloaded;
    try {
      downloaded = await recognizer.isModelDownloaded(lang);
    } on Object catch (e) {
      debugPrint('Cannot check the handwriting model for $lang: $e');
      return;
    }
    if (_disposed || lang != language) return;
    _model = downloaded ? ModelStatus.downloaded : ModelStatus.missing;
    notifyListeners();
  }

  /// Downloads [language]'s model ([wifiOnly]: wait for Wi-Fi). Returns
  /// whether it is on the device afterwards.
  Future<bool> download({bool wifiOnly = false}) async {
    if (!isSupported) return false;
    if (_model == ModelStatus.downloaded) return true;
    final lang = language;
    _model = ModelStatus.downloading;
    _downloadError = null;
    notifyListeners();
    try {
      await recognizer.downloadModel(lang, wifiOnly: wifiOnly);
      if (_disposed) return false;
      if (lang == language) _model = ModelStatus.downloaded;
    } on Object catch (e) {
      if (_disposed) return false;
      _downloadError = e;
      if (lang == language) _model = ModelStatus.missing;
    }
    notifyListeners();
    if (lang != language) {
      await refreshModel();
    } else {
      _updateIndexer();
    }
    return _model == ModelStatus.downloaded;
  }

  /// Readings of [strokes] (e.g. a lasso selection), best first. Throws if
  /// recognition is unsupported or the model is missing.
  Future<List<RecognitionCandidate>> recognize(List<Stroke> strokes, {Size? writingArea}) {
    if (!isSupported) return Future.error(UnsupportedError(unsupportedReason));
    final ordered = [...strokes.where((s) => !s.tool.isHighlighter)]..sort(Stroke.paintOrder);
    return recognizer.recognize(ordered, language: language, writingArea: writingArea);
  }

  void _updateIndexer() {
    if (_disposed) return;
    if (isSupported && indexingEnabled && _model == ModelStatus.downloaded) {
      indexer.start();
    } else {
      indexer.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    indexer.dispose();
    recognizer.dispose();
    super.dispose();
  }
}
