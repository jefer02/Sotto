#ifndef RUNNER_NATIVE_BRIDGE_H_
#define RUNNER_NATIVE_BRIDGE_H_

#include <windows.h>

#include <cstddef>
#include <cstdint>

// The browser extension's way in (services/screen/browser_bridge.dart on
// the Dart side). Plain-C boundary, like forms.h.
//
// The app listens on \\.\pipe\sotto-bridge-<user SID>: the pipe's DACL
// grants only the current user, remote clients are rejected, and each
// client's process token must belong to the current user before a byte is
// read. Bytes are passed through as they arrive; framing (4-byte length +
// JSON) is checked on the Dart side.
//
// The same executable is the native messaging host: a browser starts it
// with its extension's origin on the command line, and it relays framed
// messages between stdin / stdout and the app's pipe.

// Events: 0 a host connected, 1 bytes arrived, 2 it went away. Called on a
// bridge thread; never after SottoBridgeStop returns.
typedef void (*SottoBridgeEvent)(void* context, int conn, int event, const uint8_t* data, size_t size);

// False when the pipe can't be created (another Sotto already owns it).
bool SottoBridgeStart(SottoBridgeEvent callback, void* context);
void SottoBridgeStop();
bool SottoBridgeWrite(int conn, const uint8_t* data, size_t size);
void SottoBridgeClose(int conn);

// HKCU\<key> (default value) = manifest_path. No admin rights needed.
bool SottoBridgeRegisterHost(const wchar_t* key, const wchar_t* manifest_path);

// Whether this process was started by a browser as the native messaging
// host: Chrome / Edge pass "chrome-extension://<id>/", Firefox the
// manifest path and the extension id; "--native-host" also works.
bool SottoBridgeIsHostLaunch();

// Runs the host until the browser closes stdin; returns the exit code.
int SottoBridgeHostMain();

#endif  // RUNNER_NATIVE_BRIDGE_H_
