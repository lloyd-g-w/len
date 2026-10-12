#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

namespace {

// Places the initial window: 1280×800 logical pixels (smaller on small
// screens), centred in the primary monitor's work area. Win32Window::Create
// takes logical coordinates and scales them by the monitor's DPI.
void InitialPlacement(Win32Window::Point* origin, Win32Window::Size* size) {
  *origin = Win32Window::Point(10, 10);
  *size = Win32Window::Size(1280, 800);
  const POINT zero = {0, 0};
  HMONITOR monitor = ::MonitorFromPoint(zero, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!::GetMonitorInfo(monitor, &info)) {
    return;
  }
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const RECT& work = info.rcWork;
  const int work_width = static_cast<int>((work.right - work.left) / scale);
  const int work_height = static_cast<int>((work.bottom - work.top) / scale);
  const int width = (std::min)(1280, work_width * 9 / 10);
  const int height = (std::min)(800, work_height * 9 / 10);
  *size = Win32Window::Size(width, height);
  *origin = Win32Window::Point(
      static_cast<int>(work.left / scale) + (work_width - width) / 2,
      static_cast<int>(work.top / scale) + (work_height - height) / 2);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // One Len per session: a second launch hands its files to the running
  // one and exits.
  SingleInstance single_instance;
  if (!single_instance.Claim()) {
    return SingleInstance::Forward(CommandLinePaths()) ? EXIT_SUCCESS
                                                       : EXIT_FAILURE;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  InitialPlacement(&origin, &size);
  if (!window.Create(L"Len", origin, size)) {
    return EXIT_FAILURE;
  }
  window.RestorePlacement();
  window.SetQuitOnClose(true);
  single_instance.Listen(window.GetHandle());

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
