#ifndef RUNNER_NATIVE_SCREEN_CAPTURE_H_
#define RUNNER_NATIVE_SCREEN_CAPTURE_H_

#include <windows.h>

#include <cstddef>

// Plain-C boundary: this library is built with exceptions (C++/WinRT needs
// them) while the runner is not, so nothing from the STL crosses it.

struct SottoCapture {
  unsigned char* jpeg;   // owned; release with SottoCaptureFree
  size_t jpeg_size;
  int width;             // encoded image, pixels
  int height;
  int left;              // captured monitor, physical pixels (virtual desktop)
  int top;
  int screen_width;
  int screen_height;
  double scale;          // monitor DPI / 96
  char method[8];        // "wgc" or "gdi"
  char error[256];
};

// Captures [monitor] (Windows.Graphics.Capture, falling back to BitBlt),
// scales it so the long side is at most [max_side] and encodes a JPEG.
// Windows with WDA_EXCLUDEFROMCAPTURE — the overlay — never appear.
bool SottoCaptureMonitor(HMONITOR monitor, int max_side, int quality, SottoCapture* out);

void SottoCaptureFree(SottoCapture* capture);

#endif  // RUNNER_NATIVE_SCREEN_CAPTURE_H_
