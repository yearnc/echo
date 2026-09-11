#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Phone-shaped window on desktop so the mobile layout can be previewed during
  // development. Size is in LOGICAL pixels -- Win32Window::Create multiplies it
  // by the monitor scale factor (1.25 here), so 390x780 becomes 488x975 physical.
  // Note: keep this file ASCII-only -- MSVC runs with code page 936 here and
  // treats C4819 (non-ASCII in source) as an error (C2220).
  // Height is capped so the window (scaled by 1.25 here) plus the title bar still
  // fits above the taskbar -- otherwise the bottom navigation bar ends up
  // off-screen and becomes unclickable.
  Win32Window::Point origin(80, 24);
  Win32Window::Size size(390, 700);
  if (!window.Create(L"\u56DE\u54CD Echo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
