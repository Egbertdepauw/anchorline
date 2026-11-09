#ifndef RUNNER_PLATFORM_DISPATCHER_H_
#define RUNNER_PLATFORM_DISPATCHER_H_

#include <windows.h>

#include <deque>
#include <functional>
#include <memory>
#include <mutex>

// Runs closures on the thread that created it: the Flutter platform thread.
//
// Flutter channel calls (method results, event sinks) must happen on the
// platform thread, while WinRT completions and events arrive on thread-pool
// threads. Post() from any thread queues a closure and wakes a message-only
// window owned by the platform thread, whose window procedure runs the
// queue. After Shutdown() nothing more runs.
class PlatformDispatcher {
 public:
  // Call on the platform thread.
  static std::shared_ptr<PlatformDispatcher> Create();

  ~PlatformDispatcher();

  PlatformDispatcher(const PlatformDispatcher&) = delete;
  PlatformDispatcher& operator=(const PlatformDispatcher&) = delete;

  // Any thread. Dropped silently after Shutdown().
  void Post(std::function<void()> task);

  // Platform thread. Drops queued tasks and destroys the window.
  void Shutdown();

 private:
  PlatformDispatcher() = default;

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void Drain();

  HWND hwnd_ = nullptr;
  std::mutex mutex_;
  std::deque<std::function<void()>> queue_;
  bool shut_down_ = false;
};

#endif  // RUNNER_PLATFORM_DISPATCHER_H_
