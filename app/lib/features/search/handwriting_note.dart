import 'package:flutter/widgets.dart';

import '../../app_services.dart';
import '../../ink/recognition/recognition_service.dart';

/// Why a search that found nothing may have missed handwriting, or null
/// when handwriting is searched here (UX_AUDIT R14-2): nothing recognises
/// it on this device (what Android read and synced is still found), or
/// Search handwriting is off.
String? handwritingSearchNote(RecognitionService recognition) {
  if (!recognition.isSupported) return 'Handwriting is searched once read on Android';
  if (!recognition.indexingEnabled) return 'Handwriting search is off in Settings';
  return null;
}

/// [handwritingSearchNote] for the app's recognition, if there is an app.
String? handwritingSearchNoteOf(BuildContext context) {
  final recognition = AppScope.maybeRead(context)?.recognition;
  return recognition == null ? null : handwritingSearchNote(recognition);
}
