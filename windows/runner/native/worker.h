#ifndef RUNNER_NATIVE_WORKER_H_
#define RUNNER_NATIVE_WORKER_H_

#include <windows.h>

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// One dedicated background thread (COM multithreaded apartment) that runs
// jobs in order. Screen capture and UI Automation reads run here so the
// platform thread — which pumps the window's messages and Flutter's — never
// waits on a slow page. A job's reply is posted back to the window as
// kWorkerReply and run there, where Flutter method results must be sent.
class NativeWorker {
 public:
  static constexpr UINT kWorkerReply = WM_APP + 0x51;

  NativeWorker() = default;
  ~NativeWorker() { Stop(); }

  NativeWorker(const NativeWorker&) = delete;
  NativeWorker& operator=(const NativeWorker&) = delete;

  // [reply_to] receives the replies (the Flutter window).
  void Start(HWND reply_to) {
    reply_to_ = reply_to;
    thread_ = std::thread([this] { Run(); });
  }

  // Jobs still queued are dropped; the running one finishes first.
  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!thread_.joinable()) return;
      stopping_ = true;
      jobs_.clear();
    }
    ready_.notify_all();
    thread_.join();
  }

  using Reply = std::function<void()>;
  using Job = std::function<Reply()>;

  // Runs [job] on the worker; [job] returns what to run on the platform
  // thread afterwards (send the method result there). If [job] throws,
  // [failed] runs there instead — every call gets an answer.
  void Post(Job job, Reply failed) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) return;
      jobs_.push_back({std::move(job), std::move(failed)});
    }
    ready_.notify_one();
  }

  // Call from the window procedure for kWorkerReply.
  static void RunReply(LPARAM lparam) {
    auto* reply = reinterpret_cast<Reply*>(lparam);
    if (*reply) (*reply)();
    delete reply;
  }

  // Replies posted but never run (the window is going away).
  static void DropReplies(HWND hwnd) {
    MSG msg;
    while (PeekMessage(&msg, hwnd, kWorkerReply, kWorkerReply, PM_REMOVE)) {
      delete reinterpret_cast<Reply*>(msg.lParam);
    }
  }

 private:
  void Run() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    for (;;) {
      Entry entry;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return stopping_ || !jobs_.empty(); });
        if (stopping_) break;
        entry = std::move(jobs_.front());
        jobs_.pop_front();
      }
      Reply done;
      try {
        done = entry.job();
      } catch (...) {
        done = std::move(entry.failed);
      }
      auto* reply = new Reply(std::move(done));
      if (!PostMessage(reply_to_, kWorkerReply, 0, reinterpret_cast<LPARAM>(reply))) delete reply;
    }
    CoUninitialize();
  }

  struct Entry {
    Job job;
    Reply failed;
  };

  HWND reply_to_ = nullptr;
  std::thread thread_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Entry> jobs_;
  bool stopping_ = false;
};

#endif  // RUNNER_NATIVE_WORKER_H_
