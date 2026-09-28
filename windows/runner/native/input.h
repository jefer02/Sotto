#ifndef RUNNER_NATIVE_INPUT_H_
#define RUNNER_NATIVE_INPUT_H_

#include <windows.h>

// Synthetic input for agent mode. Coordinates are physical pixels in
// virtual-desktop space (the runner is per-monitor DPI aware v2).
// Plain-C boundary, like screen_capture.h.

bool SottoMouseMove(int x, int y);
// button: 0 = left, 1 = right. count: 1 or 2.
bool SottoMouseClick(int x, int y, int button, int count);
// Wheel notches; positive dy scrolls down, positive dx scrolls right.
bool SottoMouseScroll(int x, int y, bool at_point, int dx, int dy);
bool SottoTypeText(const wchar_t* text);
// Key names ("ctrl", "a", "enter"…) pressed together, modifiers first.
// Returns false (and presses nothing) if a name is unknown.
bool SottoPressKeys(const char* const* keys, int count);
// Lets go of every modifier and mouse button — the emergency stop.
void SottoReleaseAll();

// The focused control, via UI Automation. Strings are truncated to fit.
bool SottoFocusedElement(bool* is_password, wchar_t* name, int name_len, wchar_t* role, int role_len);

#endif  // RUNNER_NATIVE_INPUT_H_
