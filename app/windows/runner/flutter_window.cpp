#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "single_instance.h"

namespace {

constexpr wchar_t kSettingsKey[] = L"Software\\Len";
constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

using flutter::EncodableMap;
using flutter::EncodableValue;

std::string BaseName(const std::string& path) {
  const size_t slash = path.find_last_of("\\/");
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter::BinaryMessenger* messenger =
      flutter_controller_->engine()->messenger();
  const auto& codec = flutter::StandardMethodCodec::GetInstance();

  window_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "len/window", &codec);
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const auto* on = std::get_if<bool>(call.arguments());
        if (call.method_name() == "setFullScreen" && on != nullptr) {
          SetFullScreen(*on);
          result->Success(EncodableValue(full_screen_));
        } else {
          result->NotImplemented();
        }
      });

  incoming_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "len/incoming_files", &codec);
  incoming_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "ready") {
          dart_ready_ = true;
          result->Success();
          SendPendingFiles();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    ::ShowWindow(GetHandle(), show_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  incoming_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RestorePlacement() {
  WINDOWPLACEMENT placement = {};
  DWORD size = sizeof(placement);
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                     RRF_RT_REG_BINARY, nullptr, &placement,
                     &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || placement.length != sizeof(placement)) {
    return;
  }
  const RECT& normal = placement.rcNormalPosition;
  if (normal.right - normal.left < 100 || normal.bottom - normal.top < 100 ||
      ::MonitorFromRect(&normal, MONITOR_DEFAULTTONULL) == nullptr) {
    return;  // Implausible, or its monitor is gone: keep the default.
  }
  show_maximized_ = placement.showCmd == SW_SHOWMAXIMIZED ||
                    (placement.flags & WPF_RESTORETOMAXIMIZED) != 0;
  // Only the normal rectangle now; the first frame shows the window.
  placement.showCmd = SW_HIDE;
  placement.flags = 0;
  // Twice: moving onto a monitor with another DPI rescales the window
  // (WM_DPICHANGED); the second call applies the exact size at that DPI.
  ::SetWindowPlacement(GetHandle(), &placement);
  ::SetWindowPlacement(GetHandle(), &placement);
}

void FlutterWindow::SavePlacement() {
  WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  if (full_screen_) {
    placement = saved_placement_;  // The window behind the full screen.
  } else if (!::GetWindowPlacement(GetHandle(), &placement)) {
    return;
  }
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                    REG_BINARY, &placement, sizeof(placement));
}

// Borderless window covering its monitor (and back), the classic way:
// https://devblogs.microsoft.com/oldnewthing/20100412-00/?p=14353
void FlutterWindow::SetFullScreen(bool full_screen) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || full_screen == full_screen_) return;
  if (full_screen) {
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    if (!::GetWindowPlacement(hwnd, &saved_placement_) ||
        !::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                          &monitor)) {
      return;
    }
    saved_style_ = ::GetWindowLong(hwnd, GWL_STYLE);
    // Without WS_MAXIMIZE too, so leaving full screen really maximises a
    // window that was maximised (SetWindowPlacement below).
    ::SetWindowLong(hwnd, GWL_STYLE,
                    saved_style_ & ~static_cast<LONG>(WS_OVERLAPPEDWINDOW |
                                                      WS_MAXIMIZE));
    const RECT& r = monitor.rcMonitor;
    ::SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left,
                   r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ::SetWindowLong(hwnd, GWL_STYLE,
                    saved_style_ & ~static_cast<LONG>(WS_MAXIMIZE));
    ::SetWindowPlacement(hwnd, &saved_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  full_screen_ = full_screen;
}

void FlutterWindow::SendPendingFiles() {
  if (!dart_ready_ || !incoming_channel_ || pending_files_.empty()) return;
  flutter::EncodableList files;
  for (const std::string& path : pending_files_) {
    files.emplace_back(EncodableMap{
        {EncodableValue("path"), EncodableValue(path)},
        {EncodableValue("name"), EncodableValue(BaseName(path))},
    });
  }
  pending_files_.clear();
  incoming_channel_->InvokeMethod(
      "files", std::make_unique<EncodableValue>(std::move(files)));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == ForwardedFilesMessage()) {
    if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
    for (std::string& path : TakeForwardedPaths()) {
      pending_files_.push_back(std::move(path));
    }
    SendPendingFiles();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      // Before Flutter, which may turn the close into an exit request.
      SavePlacement();
      break;
    case WM_ENDSESSION:
      if (wparam) SavePlacement();  // Logoff, shutdown, installer upgrade.
      break;
    case WM_DESTROY:
      SavePlacement();  // Also when Dart exits the app (no WM_CLOSE).
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
