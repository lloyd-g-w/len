#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <string>
#include <vector>

// Posted to the main window with a heap-allocated std::vector<std::string>*
// (UTF-8 absolute paths, possibly empty) in LPARAM; the window takes
// ownership. Sent when another `len.exe` forwarded its files.
constexpr UINT kForwardedFilesMessage = WM_APP + 1;

// One Len process per Windows session owns the database. A second launch
// ("Open with Len", a file association, the Start menu) hands its files to
// the running one over a named pipe and exits, like the Linux runner's
// GApplication forwarding.
//
// A named mutex marks the running instance; a pipe server thread in it
// receives "LEN1\n" followed by '\n'-separated UTF-8 paths. The pipe uses
// the default security descriptor, so only the same user (and SYSTEM /
// administrators) can write to it, and remote clients are rejected.
// LEN_MULTI_INSTANCE=1 turns this off (tests, screenshots).
class SingleInstance {
 public:
  SingleInstance();
  ~SingleInstance();

  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // Whether this process is the one instance (or single-instance mode is
  // off). Call once, before creating the window.
  bool Claim();

  // From a second process: delivers [paths] to the running instance,
  // retrying for a few seconds while it starts. Returns whether they arrived.
  static bool Forward(const std::vector<std::wstring>& paths);

  // In the instance: serves the pipe on a background thread, posting
  // kForwardedFilesMessage to [window] for every launch forwarded to it.
  void Listen(HWND window);

 private:
  HANDLE mutex_ = nullptr;
  bool enabled_ = true;
};

// Absolute paths of this process's file arguments (anything not starting
// with '-'), resolved against its working directory.
std::vector<std::wstring> CommandLinePaths();

#endif  // RUNNER_SINGLE_INSTANCE_H_
