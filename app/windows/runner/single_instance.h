#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <string>
#include <vector>

// One Len process per Windows session owns the database. A second launch
// ("Open with Len", a file association, the Start menu) hands its files to
// the running one over a named pipe and exits, like the Linux runner's
// GApplication forwarding.
//
// * A named mutex (Local\dev.len.len.instance) marks the running instance.
// * It creates the pipe \\.\pipe\dev.len.len-<session> at once (so launches
//   during its start-up already queue), readable and writable by the current
//   user only, local clients only, never shared with another creator
//   (FILE_FLAG_FIRST_PIPE_INSTANCE).
// * A client writes "LEN1\n" + '\n'-separated UTF-8 absolute paths and
//   waits for a one-byte acknowledgement, sent once the window has been
//   told. It connects with identification-level impersonation only and
//   checks that the server runs in its own session.
// * Without an acknowledgement (the running Len was just closing) the
//   second launch waits for the mutex and becomes the instance itself.
// LEN_MULTI_INSTANCE (set to anything) turns this off (tests, screenshots).
class SingleInstance {
 public:
  SingleInstance();
  ~SingleInstance();

  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // Whether this process is the one instance (or single-instance mode is
  // off). Creates the pipe when it is.
  bool Claim();

  // Claim, retried for up to [timeout_ms] while another instance exits.
  bool ClaimWithin(DWORD timeout_ms);

  // From a second process: delivers [paths] to the running instance,
  // retrying for a few seconds while it starts. Returns whether the
  // running instance acknowledged them.
  static bool Forward(const std::vector<std::wstring>& paths);

  // In the instance: serves the pipe on a background thread. Each forwarded
  // launch queues its paths (TakeForwardedPaths) and posts
  // ForwardedFilesMessage() to [window].
  void Listen(HWND window);

  // Releases the instance (after the window is gone), so a launch from now
  // on starts a new Len instead of forwarding to this one.
  void Release();

 private:
  HANDLE mutex_ = nullptr;
  HANDLE pipe_ = INVALID_HANDLE_VALUE;
  bool enabled_ = true;
};

// The window message posted for forwarded launches (WPARAM/LPARAM unused).
UINT ForwardedFilesMessage();

// Forwarded paths (UTF-8, absolute, or `len:` links) not yet taken;
// thread-safe.
std::vector<std::string> TakeForwardedPaths();

// Absolute paths of this process's file arguments (anything not starting
// with '-'), resolved against its working directory; `len:` links as given.
std::vector<std::wstring> CommandLinePaths();

#endif  // RUNNER_SINGLE_INSTANCE_H_
