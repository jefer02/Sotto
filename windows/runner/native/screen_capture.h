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
  char* ocr_json;        // owned, or null: see [ocr] below
};

// Captures [monitor] (Windows.Graphics.Capture, falling back to BitBlt),
// scales it so the long side is at most [max_side] and encodes a JPEG.
// Windows with WDA_EXCLUDEFROMCAPTURE — the overlay — never appear.
// With [ocr], the text on it too (Windows.Media.Ocr, on this computer, on
// the full-size capture): {"lines":[{"text","box":[x,y,w,h],"words":
// [[x,y,w,h,"word"],…]}]}, boxes in the encoded image's pixels.
bool SottoCaptureMonitor(HMONITOR monitor, int max_side, int quality, bool ocr, SottoCapture* out);

void SottoCaptureFree(SottoCapture* capture);

// The text on [bgra] ([width] × [height] pixels, top-down, 4 bytes each),
// read with Windows.Media.Ocr in the same JSON as [SottoCaptureMonitor]'s
// ocr_json, boxes in its pixels. Null when OCR is unavailable; release the
// result with SottoTextFree.
char* SottoRecognizeBgra(const unsigned char* bgra, int width, int height);

void SottoTextFree(char* text);

#endif  // RUNNER_NATIVE_SCREEN_CAPTURE_H_
