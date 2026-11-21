#include "single_instance.h"

namespace single_instance {
namespace {

constexpr wchar_t kMutexName[] = L"Local\\scglow.single";
constexpr wchar_t kWindowProp[] = L"scglow.main";
constexpr wchar_t kActivateMessage[] = L"scglow.activate";

HANDLE g_mutex = nullptr;

BOOL CALLBACK FindTagged(HWND hwnd, LPARAM out) {
  if (GetPropW(hwnd, kWindowProp) != nullptr) {
    *reinterpret_cast<HWND*>(out) = hwnd;
    return FALSE;
  }
  return TRUE;
}

HWND FindRunningWindow() {
  HWND found = nullptr;
  EnumWindows(FindTagged, reinterpret_cast<LPARAM>(&found));
  return found;
}

}

UINT ActivateMessage() {
  static const UINT message = RegisterWindowMessageW(kActivateMessage);
  return message;
}

bool Acquire() {
  // A build from before the rename may still be running (tray): show it instead of starting twice.
  if (HWND legacy = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Afterglow")) {
    BringToFront(legacy);
    return false;
  }
  g_mutex = CreateMutexW(nullptr, FALSE, kMutexName);
  // Without the mutex there is nothing to coordinate with, so run as the first instance.
  if (g_mutex == nullptr || GetLastError() != ERROR_ALREADY_EXISTS) {
    return true;
  }
  HWND running = nullptr;
  for (int i = 0; i < 40 && running == nullptr; ++i) {
    running = FindRunningWindow();
    if (running == nullptr) Sleep(100);
  }
  if (running != nullptr) {
    DWORD pid = 0;
    GetWindowThreadProcessId(running, &pid);
    AllowSetForegroundWindow(pid);
    PostMessageW(running, ActivateMessage(), 0, 0);
  }
  CloseHandle(g_mutex);
  g_mutex = nullptr;
  return false;
}

void TagWindow(HWND window) {
  SetPropW(window, kWindowProp, reinterpret_cast<HANDLE>(1));
}

void UntagWindow(HWND window) { RemovePropW(window, kWindowProp); }

void BringToFront(HWND window) {
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else if (!IsWindowVisible(window)) {
    ShowWindow(window, SW_SHOW);
  }
  SetForegroundWindow(window);
}

}
