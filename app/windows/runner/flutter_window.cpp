#include "flutter_window.h"

#include <algorithm>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "actit_pass_storage/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "showLogin") {
          SetLoginWindowMode();
          result->Success();
        } else if (call.method_name() == "showLoginExpanded") {
          SetLoginWindowMode(true);
          result->Success();
        } else if (call.method_name() == "showMain") {
          SetMainWindowMode();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetLoginWindowMode(bool expanded) {
  SetWindowMode(true, expanded);
}

void FlutterWindow::SetMainWindowMode() {
  SetWindowMode(false, false);
}

void FlutterWindow::SetWindowMode(bool login, bool expanded) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE,
                   login ? WS_POPUP : WS_OVERLAPPEDWINDOW);
  // Use Unicode escapes so the taskbar title does not depend on the compiler's
  // source-file code page.
  SetWindowText(hwnd,
                login ? L"\u041F\u0430\u0440\u043E\u043B\u044C"
                      : L"Pass Storage");

  const double scale = GetDpiForWindow(hwnd) / 96.0;
  int width = static_cast<int>((login ? 562 : 1280) * scale);
  const int login_height = expanded ? 650 : 590;
  int height = static_cast<int>((login ? login_height : 720) * scale);

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const RECT work = monitor_info.rcWork;
  const int work_width = work.right - work.left;
  const int work_height = work.bottom - work.top;
  width = std::min(width, work_width);
  height = std::min(height, work_height);
  const int x = work.left + (work_width - width) / 2;
  const int y = work.top + (work_height - height) / 2;

  SetWindowPos(hwnd, HWND_TOP, x, y, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The login window is frameless. Let the Win32 host classify its top strip
  // as HTCAPTION before Flutter gets a chance to consume WM_NCHITTEST. This
  // keeps the window draggable with a mouse, pen, or touch gesture.
  if (message == WM_NCHITTEST) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
