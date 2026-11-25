#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "single_instance.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

// Tear down while the object is whole: the controller's view sends messages to
// this window as it is destroyed, and member destructors would leave dangling
// pointers for MessageHandler to use.
FlutterWindow::~FlutterWindow() { Destroy(); }

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
  smtc_ = std::make_unique<SmtcPlugin>(
      flutter_controller_->engine()->messenger(), GetHandle());
  tray_ = std::make_unique<TrayPlugin>(
      flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  single_instance::TagWindow(GetHandle());

  // The window is shown from Dart (window_manager, waitUntilReadyToShow)
  // once the frameless style and size are applied, so nothing flashes.

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (HWND handle = GetHandle()) single_instance::UntagWindow(handle);
  smtc_ = nullptr;
  tray_ = nullptr;
  flutter_controller_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == single_instance::ActivateMessage()) {
    // Native restore first so the window appears even if Dart is busy, then
    // let Dart run its usual "show" path (window_manager state, active flag).
    single_instance::BringToFront(hwnd);
    if (tray_) tray_->RequestShow();
    return 0;
  }
  if (smtc_ && smtc_->HandleWindowMessage(message, wparam, lparam)) {
    return 0;
  }
  if (tray_ && tray_->HandleWindowMessage(message, wparam, lparam)) {
    return 0;
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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
