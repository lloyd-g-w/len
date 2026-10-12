#include "single_instance.h"

#include <sddl.h>
#include <shellapi.h>

#include <memory>
#include <mutex>
#include <thread>

#include "utils.h"

namespace {

constexpr char kHeader[] = "LEN1\n";
constexpr char kAck = '\x06';
constexpr DWORD kMaxMessage = 1 << 20;  // 1 MiB of paths is plenty.
constexpr ULONGLONG kForwardTimeoutMs = 10000;

std::mutex g_inbox_mutex;
std::vector<std::string> g_inbox;

DWORD SessionOf(DWORD process) {
  DWORD session = 0;
  ::ProcessIdToSessionId(process, &session);
  return session;
}

// Per session, so two users signed in at once each get their own Len.
std::wstring PipeName() {
  return L"\\\\.\\pipe\\dev.len.len-" +
         std::to_wstring(SessionOf(::GetCurrentProcessId()));
}

// "D:P(A;;GA;;;<user SID>)": only the current user may open the pipe.
std::wstring CurrentUserOnlySddl() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return std::wstring();
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::unique_ptr<BYTE[]> buffer(new BYTE[size]);
  std::wstring sddl;
  LPWSTR sid = nullptr;
  if (size > 0 &&
      ::GetTokenInformation(token, TokenUser, buffer.get(), size, &size) &&
      ::ConvertSidToStringSidW(
          reinterpret_cast<TOKEN_USER*>(buffer.get())->User.Sid, &sid)) {
    sddl = std::wstring(L"D:P(A;;GA;;;") + sid + L")";
    ::LocalFree(sid);
  }
  ::CloseHandle(token);
  return sddl;
}

HANDLE CreatePipe() {
  const std::wstring sddl = CurrentUserOnlySddl();
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (sddl.empty() ||
      !::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) {
    return INVALID_HANDLE_VALUE;
  }
  SECURITY_ATTRIBUTES attributes = {sizeof(SECURITY_ATTRIBUTES), descriptor,
                                    FALSE};
  // FIRST_PIPE_INSTANCE: fail rather than join a pipe someone else made.
  HANDLE pipe = ::CreateNamedPipeW(
      PipeName().c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      1, 1, kMaxMessage, 0, &attributes);
  ::LocalFree(descriptor);
  return pipe;
}

// Splits a received message into paths; false if the header is missing.
bool ParseMessage(const std::string& message, std::vector<std::string>* paths) {
  const size_t header = sizeof(kHeader) - 1;
  if (message.compare(0, header, kHeader) != 0) return false;
  size_t start = header;
  while (start < message.size()) {
    size_t end = message.find('\n', start);
    if (end == std::string::npos) end = message.size();
    if (end > start) paths->push_back(message.substr(start, end - start));
    start = end + 1;
  }
  return true;
}

// Reads one whole message from a connected pipe; empty on failure.
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

void Serve(HWND window, HANDLE pipe) {
  for (;;) {
    // A client may connect between iterations: ERROR_PIPE_CONNECTED.
    const bool connected = ::ConnectNamedPipe(pipe, nullptr)
                               ? true
                               : ::GetLastError() == ERROR_PIPE_CONNECTED;
    if (connected) {
      std::vector<std::string> paths;
      if (ParseMessage(ReadMessage(pipe), &paths)) {
        {
          std::lock_guard<std::mutex> lock(g_inbox_mutex);
          for (std::string& path : paths) g_inbox.push_back(std::move(path));
        }
        if (::PostMessage(window, ForwardedFilesMessage(), 0, 0)) {
          DWORD written = 0;
          ::WriteFile(pipe, &kAck, 1, &written, nullptr);
          ::FlushFileBuffers(pipe);  // Until the client has read it.
        }
      }
    }
    ::DisconnectNamedPipe(pipe);
  }
}

}  // namespace

SingleInstance::SingleInstance() = default;

SingleInstance::~SingleInstance() { Release(); }

bool SingleInstance::Claim() {
  if (::GetEnvironmentVariableW(L"LEN_MULTI_INSTANCE", nullptr, 0) > 0) {
    enabled_ = false;
    return true;
  }
  if (mutex_ != nullptr) return true;
  HANDLE mutex = ::CreateMutexW(nullptr, FALSE, L"Local\\dev.len.len.instance");
  if (mutex == nullptr) {
    // ACCESS_DENIED: an elevated Len runs; anything else: cannot tell.
    return ::GetLastError() != ERROR_ACCESS_DENIED;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::CloseHandle(mutex);
    return false;
  }
  mutex_ = mutex;
  pipe_ = CreatePipe();  // Without it Len still runs, just doesn't forward.
  return true;
}

bool SingleInstance::ClaimWithin(DWORD timeout_ms) {
  const ULONGLONG deadline = ::GetTickCount64() + timeout_ms;
  while (!Claim()) {
    if (::GetTickCount64() >= deadline) return false;
    ::Sleep(100);
  }
  return true;
}

bool SingleInstance::Forward(const std::vector<std::wstring>& paths) {
  std::string message = kHeader;
  for (const std::wstring& path : paths) {
    const std::string utf8 = Utf8FromUtf16(path.c_str());
    if (!utf8.empty()) message += utf8 + "\n";
  }
  const std::wstring name = PipeName();
  const ULONGLONG deadline = ::GetTickCount64() + kForwardTimeoutMs;
  while (::GetTickCount64() < deadline) {
    HANDLE pipe = ::CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                                nullptr, OPEN_EXISTING,
                                SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
                                nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      // Busy (another launch is being served) or not there (the running
      // Len is starting or closing): wait and retry.
      if (::GetLastError() != ERROR_PIPE_BUSY ||
          !::WaitNamedPipeW(name.c_str(), 100)) {
        ::Sleep(100);
      }
      continue;
    }
    // Only a Len in this session may receive the paths (and the right to
    // come to the front, which this just-started process may hand on).
    ULONG server = 0;
    bool delivered = false;
    if (::GetNamedPipeServerProcessId(pipe, &server) &&
        SessionOf(server) == SessionOf(::GetCurrentProcessId())) {
      ::AllowSetForegroundWindow(server);
      DWORD written = 0;
      char ack = 0;
      DWORD read = 0;
      delivered =
          ::WriteFile(pipe, message.data(), static_cast<DWORD>(message.size()),
                      &written, nullptr) &&
          written == message.size() &&
          ::ReadFile(pipe, &ack, 1, &read, nullptr) && read == 1 &&
          ack == kAck;
    }
    ::CloseHandle(pipe);
    return delivered;
  }
  return false;
}

void SingleInstance::Listen(HWND window) {
  if (!enabled_ || pipe_ == INVALID_HANDLE_VALUE) return;
  // Detached: it blocks in ConnectNamedPipe until the process exits (the
  // pipe handle stays open until then, see Release).
  std::thread(Serve, window, pipe_).detach();
}

void SingleInstance::Release() {
  // The pipe handle belongs to the serving thread, which outlives this;
  // closing the mutex is enough for a new launch to start a fresh Len.
  // Launches forwarded meanwhile get no acknowledgement (the window is
  // gone) and become the instance themselves.
  if (mutex_ != nullptr) {
    ::CloseHandle(mutex_);
    mutex_ = nullptr;
  }
}

UINT ForwardedFilesMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"dev.len.len.forward");
  return message;
}

std::vector<std::string> TakeForwardedPaths() {
  std::lock_guard<std::mutex> lock(g_inbox_mutex);
  std::vector<std::string> paths;
  paths.swap(g_inbox);
  return paths;
}

std::vector<std::wstring> CommandLinePaths() {
  std::vector<std::wstring> paths;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return paths;
  for (int i = 1; i < argc; i++) {
    const wchar_t* arg = argv[i];
    if (arg[0] == L'\0' || arg[0] == L'-') continue;
    const DWORD size = ::GetFullPathNameW(arg, 0, nullptr, nullptr);
    if (size == 0) continue;
    std::wstring full(size, L'\0');
    const DWORD length = ::GetFullPathNameW(arg, size, full.data(), nullptr);
    if (length == 0 || length >= size) continue;
    full.resize(length);
    paths.push_back(std::move(full));
  }
  ::LocalFree(argv);
  return paths;
}
