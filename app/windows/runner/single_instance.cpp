#include "single_instance.h"

#include <shellapi.h>

#include <thread>

#include "utils.h"

namespace {

constexpr char kHeader[] = "LEN1\n";
constexpr DWORD kMaxMessage = 1 << 20;  // 1 MiB of paths is plenty.
constexpr int kForwardAttempts = 100;   // × 100 ms

// Per session, so two users signed in at once each get their own Len.
std::wstring SessionSuffix() {
  DWORD session = 0;
  ::ProcessIdToSessionId(::GetCurrentProcessId(), &session);
  return std::to_wstring(session);
}

std::wstring PipeName() {
  return L"\\\\.\\pipe\\dev.len.len-" + SessionSuffix();
}

// Splits a received message into paths; empty if the header is missing.
std::vector<std::string> ParseMessage(const std::string& message) {
  std::vector<std::string> paths;
  const size_t header = sizeof(kHeader) - 1;
  if (message.compare(0, header, kHeader) != 0) return paths;
  size_t start = header;
  while (start < message.size()) {
    size_t end = message.find('\n', start);
    if (end == std::string::npos) end = message.size();
    if (end > start) paths.push_back(message.substr(start, end - start));
    start = end + 1;
  }
  return paths;
}

// Reads one whole message from a connected pipe.
std::string ReadMessage(HANDLE pipe) {
  std::string message;
  char buffer[4096];
  for (;;) {
    DWORD read = 0;
    const BOOL ok = ::ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr);
    message.append(buffer, read);
    if (ok) return message;
    if (::GetLastError() != ERROR_MORE_DATA || message.size() > kMaxMessage) {
      return std::string();
    }
  }
}

void Serve(HWND window, std::wstring name) {
  for (;;) {
    // FIRST_PIPE_INSTANCE: fail rather than join a pipe someone else made.
    HANDLE pipe = ::CreateNamedPipeW(
        name.c_str(), PIPE_ACCESS_INBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT |
            PIPE_REJECT_REMOTE_CLIENTS,
        1, 0, kMaxMessage, 0, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) return;
    const bool connected = ::ConnectNamedPipe(pipe, nullptr)
                               ? true
                               : ::GetLastError() == ERROR_PIPE_CONNECTED;
    if (connected) {
      const std::string message = ReadMessage(pipe);
      if (!message.empty()) {
        auto* paths = new std::vector<std::string>(ParseMessage(message));
        if (!::PostMessage(window, kForwardedFilesMessage, 0,
                           reinterpret_cast<LPARAM>(paths))) {
          delete paths;
        }
      }
    }
    ::DisconnectNamedPipe(pipe);
    ::CloseHandle(pipe);
  }
}

}  // namespace

SingleInstance::SingleInstance() = default;

SingleInstance::~SingleInstance() {
  if (mutex_ != nullptr) ::CloseHandle(mutex_);
}

bool SingleInstance::Claim() {
  wchar_t value[8];
  if (::GetEnvironmentVariableW(L"LEN_MULTI_INSTANCE", value, 8) > 0) {
    enabled_ = false;
    return true;
  }
  const std::wstring name = L"Local\\dev.len.len.instance";
  mutex_ = ::CreateMutexW(nullptr, FALSE, name.c_str());
  if (mutex_ == nullptr) return true;  // Cannot tell: run.
  return ::GetLastError() != ERROR_ALREADY_EXISTS;
}

bool SingleInstance::Forward(const std::vector<std::wstring>& paths) {
  std::string message = kHeader;
  for (const std::wstring& path : paths) {
    const std::string utf8 = Utf8FromUtf16(path.c_str());
    if (!utf8.empty()) message += utf8 + "\n";
  }
  const std::wstring name = PipeName();
  for (int attempt = 0; attempt < kForwardAttempts; attempt++) {
    HANDLE pipe = ::CreateFileW(name.c_str(), GENERIC_WRITE, 0, nullptr,
                                OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      // This process was just started by the user, so it may hand the
      // right to come to the front to the running Len.
      ULONG server = 0;
      if (::GetNamedPipeServerProcessId(pipe, &server)) {
        ::AllowSetForegroundWindow(server);
      }
      DWORD written = 0;
      const BOOL ok =
          ::WriteFile(pipe, message.data(), static_cast<DWORD>(message.size()),
                      &written, nullptr);
      ::CloseHandle(pipe);
      return ok && written == message.size();
    }
    // Busy (another launch is being served) or not created yet (the
    // running Len is still starting): wait and retry.
    if (::GetLastError() == ERROR_PIPE_BUSY) {
      ::WaitNamedPipeW(name.c_str(), 100);
    } else {
      ::Sleep(100);
    }
  }
  return false;
}

void SingleInstance::Listen(HWND window) {
  if (!enabled_ || mutex_ == nullptr) return;
  // Detached: it blocks in ConnectNamedPipe until the process exits.
  std::thread(Serve, window, PipeName()).detach();
}

std::vector<std::wstring> CommandLinePaths() {
  std::vector<std::wstring> paths;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return paths;
  for (int i = 1; i < argc; i++) {
    const wchar_t* arg = argv[i];
    if (arg[0] == L'\0' || arg[0] == L'-') continue;
    wchar_t full[MAX_PATH * 4];
    const DWORD length = ::GetFullPathNameW(arg, MAX_PATH * 4, full, nullptr);
    if (length > 0 && length < MAX_PATH * 4) paths.emplace_back(full, length);
  }
  ::LocalFree(argv);
  return paths;
}
