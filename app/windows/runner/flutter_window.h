#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// The window hosting Len's Flutter view. Besides the view it:
//  * remembers its placement (size, position, maximised) across runs
//    (HKCU\Software\Len, value WindowPlacement);
//  * serves "len/window" (`setFullScreen(bool)`, presentation mode);
//  * serves "len/incoming_files": files forwarded by a second launch
//    (single_instance.h) reach Dart once it says it is `ready`.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Applies the placement saved when Len last closed, if its monitor still
  // exists. Call after Create, before the window is shown.
  void RestorePlacement();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SavePlacement();
  void SetFullScreen(bool full_screen);
  void SendPendingFiles();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      incoming_channel_;

  // Show maximised (the restored placement was maximised).
  bool show_maximized_ = false;

  // Full screen: the style and placement to return to.
  bool full_screen_ = false;
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_ = {sizeof(WINDOWPLACEMENT)};

  // Forwarded files waiting for Dart's "ready" (UTF-8 paths).
  bool dart_ready_ = false;
  std::vector<std::string> pending_files_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
