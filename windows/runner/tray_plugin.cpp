#include "tray_plugin.h"

#include <flutter/standard_method_codec.h>

#include "resource.h"

namespace {

constexpr UINT kIconId = 1;
constexpr UINT kCmdToggle = 1;
constexpr UINT kCmdNext = 2;
constexpr UINT kCmdShow = 3;
constexpr UINT kCmdQuit = 4;

std::wstring Widen(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

std::string StringArg(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return "";
  if (auto s = std::get_if<std::string>(&it->second)) return *s;
  return "";
}

bool BoolArg(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return false;
  if (auto b = std::get_if<bool>(&it->second)) return *b;
  return false;
}

std::wstring EscapeAmp(const std::wstring& s) {
  std::wstring out;
  for (wchar_t c : s) {
    if (c == L'&') out += L'&';
    out += c;
  }
  return out;
}

}

TrayPlugin::TrayPlugin(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window),
      taskbar_created_(RegisterWindowMessage(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "scglow/tray",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  AddIcon();
}

TrayPlugin::~TrayPlugin() {
  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = window_;
  nid.uID = kIconId;
  Shell_NotifyIcon(NIM_DELETE, &nid);
}

void TrayPlugin::AddIcon() {
  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = window_;
  nid.uID = kIconId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = static_cast<HICON>(
      LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  std::wstring tip = L"scglow";
  if (has_track_) tip += L" \u2014 " + title_;
  wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);
  if (!Shell_NotifyIcon(NIM_MODIFY, &nid)) Shell_NotifyIcon(NIM_ADD, &nid);
}

void TrayPlugin::Send(const char* action) {
  channel_->InvokeMethod("action",
                         std::make_unique<flutter::EncodableValue>(action));
}

void TrayPlugin::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  std::wstring header = L"scglow";
  if (has_track_) {
    header += L" \u2014 " + title_;
    if (!artist_.empty()) header += L" \u00B7 " + artist_;
  }
  if (header.size() > 60) header = header.substr(0, 59) + L"\u2026";
  AppendMenu(menu, MF_STRING | MF_GRAYED, 0, EscapeAmp(header).c_str());
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  UINT track_flags = MF_STRING | (has_track_ ? 0 : MF_GRAYED);
  AppendMenu(menu, track_flags, kCmdToggle, playing_ ? L"Pause" : L"Play");
  AppendMenu(menu, track_flags, kCmdNext, L"Next");
  AppendMenu(menu, MF_STRING, kCmdShow, L"Show");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kCmdQuit, L"Quit");

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(window_);
  UINT cmd = TrackPopupMenu(menu,
                            TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                            pt.x, pt.y, 0, window_, nullptr);
  PostMessage(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  switch (cmd) {
    case kCmdToggle:
      Send("toggle");
      break;
    case kCmdNext:
      Send("next");
      break;
    case kCmdShow:
      Send("show");
      break;
    case kCmdQuit:
      Send("quit");
      break;
  }
}

bool TrayPlugin::HandleWindowMessage(UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == taskbar_created_) {
    AddIcon();
    return false;
  }
  if (message != kTrayMessage) return false;
  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      Send("show");
      break;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      ShowMenu();
      break;
  }
  return true;
}

void TrayPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "update") {
    if (auto map = std::get_if<flutter::EncodableMap>(call.arguments())) {
      playing_ = BoolArg(*map, "playing");
      has_track_ = BoolArg(*map, "hasTrack");
      title_ = Widen(StringArg(*map, "title"));
      artist_ = Widen(StringArg(*map, "artist"));
      AddIcon();
    }
    result->Success();
    return;
  }
  result->NotImplemented();
}
