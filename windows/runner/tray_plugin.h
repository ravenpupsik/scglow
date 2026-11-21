#ifndef RUNNER_TRAY_PLUGIN_H_
#define RUNNER_TRAY_PLUGIN_H_

#include <windows.h>
#include <shellapi.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

class TrayPlugin {
 public:
  static constexpr UINT kTrayMessage = WM_APP + 0x61;

  TrayPlugin(flutter::BinaryMessenger* messenger, HWND window);
  ~TrayPlugin();

  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

  void RequestShow() { Send("show"); }

 private:
  void AddIcon();
  void ShowMenu();
  void Send(const char* action);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_;
  UINT taskbar_created_;
  bool playing_ = false;
  bool has_track_ = false;
  std::wstring title_;
  std::wstring artist_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif
