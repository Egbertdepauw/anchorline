#include "platform_dispatcher.h"

#include <utility>

namespace {

constexpr wchar_t kWindowClass[] = L"AnchorlinePlatformDispatcher";
constexpr UINT kRunQueue = WM_APP + 0x42;

void RegisterWindowClassOnce() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = DefWindowProcW;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kWindowClass;
  RegisterClassExW(&wc);
  registered = true;
}

}  // namespace

std::shared_ptr<PlatformDispatcher> PlatformDispatcher::Create() {
  RegisterWindowClassOnce();
  std::shared_ptr<PlatformDispatcher> d(new PlatformDispatcher());
  d->hwnd_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                             nullptr, GetModuleHandleW(nullptr), nullptr);
  if (d->hwnd_) {
    SetWindowLongPtrW(d->hwnd_, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(d.get()));
    SetWindowLongPtrW(d->hwnd_, GWLP_WNDPROC,
                      reinterpret_cast<LONG_PTR>(&PlatformDispatcher::WndProc));
  }
  return d;
}

PlatformDispatcher::~PlatformDispatcher() {
  // Shutdown() normally ran already, on the platform thread. A window can
  // only be destroyed by the thread that owns it, so a stray destruction
  // elsewhere just leaves it to the process exit.
}

void PlatformDispatcher::Post(std::function<void()> task) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (shut_down_ || !hwnd_) return;
  queue_.push_back(std::move(task));
  // Under the lock, so Shutdown() can't destroy the window in between.
  PostMessageW(hwnd_, kRunQueue, 0, 0);
}

void PlatformDispatcher::Shutdown() {
  HWND hwnd = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    shut_down_ = true;
    queue_.clear();
    hwnd = hwnd_;
    hwnd_ = nullptr;
  }
  if (hwnd) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    DestroyWindow(hwnd);
  }
}

void PlatformDispatcher::Drain() {
  std::deque<std::function<void()>> tasks;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (shut_down_) return;
    tasks.swap(queue_);
  }
  for (auto& task : tasks) {
    task();
  }
}

LRESULT CALLBACK PlatformDispatcher::WndProc(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
  if (message == kRunQueue) {
    auto* self = reinterpret_cast<PlatformDispatcher*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self) self->Drain();
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
