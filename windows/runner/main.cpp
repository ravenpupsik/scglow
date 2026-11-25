#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_identity.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!single_instance::Acquire()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  InitAppIdentity();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"scglow", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Quit posts WM_QUIT without destroying the window; destroy it here, rather
  // than from implicit destructors. This also removes the tray icon and SMTC.
  window.Destroy();
  // State is saved and the log flushed by Dart before quitting. Skip DLL
  // teardown: the WebView plugin's static WinRT objects crash in coremessaging
  // when released at process exit.
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
