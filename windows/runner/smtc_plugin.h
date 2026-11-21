#ifndef RUNNER_SMTC_PLUGIN_H_
#define RUNNER_SMTC_PLUGIN_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class SmtcPlugin {
 public:
  static constexpr UINT kButtonMessage = WM_APP + 0x51;
  static constexpr UINT kSeekMessage = WM_APP + 0x52;

  SmtcPlugin(flutter::BinaryMessenger* messenger, HWND window);
  ~SmtcPlugin();

  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<State> state_;
};

#endif
