import 'dart:io';

import 'media_controls_android.dart';
import 'media_controls_api.dart';
import 'mpris_native.dart';

/// Makes this platform's media controls; null where there are none.
MediaControls Function()? systemMediaControls() {
  if (Platform.isAndroid) return AndroidMediaControls.new;
  if (Platform.isLinux) return MprisControls.new;
  return null;
}
