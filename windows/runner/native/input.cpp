#include "input.h"

#include <ole2.h>
#include <oleauto.h>
#include <uiautomation.h>

#include <cstring>
#include <cwchar>
#include <string>
#include <vector>

#include <winrt/base.h>

namespace {

void Send(std::vector<INPUT>& inputs) {
  if (!inputs.empty()) SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

INPUT Mouse(DWORD flags, DWORD data = 0) {
  INPUT in{};
  in.type = INPUT_MOUSE;
  in.mi.dwFlags = flags;
  in.mi.mouseData = data;
  return in;
}

bool IsExtended(WORD vk) {
  switch (vk) {
    case VK_LEFT: case VK_RIGHT: case VK_UP: case VK_DOWN:
    case VK_HOME: case VK_END: case VK_PRIOR: case VK_NEXT:
    case VK_INSERT: case VK_DELETE: case VK_RCONTROL: case VK_RMENU:
    case VK_LWIN: case VK_RWIN: case VK_APPS:
      return true;
    default:
      return false;
  }
}

INPUT Key(WORD vk, bool up) {
  INPUT in{};
  in.type = INPUT_KEYBOARD;
  in.ki.wVk = vk;
  in.ki.wScan = static_cast<WORD>(MapVirtualKeyW(vk, MAPVK_VK_TO_VSC));
  in.ki.dwFlags = (up ? KEYEVENTF_KEYUP : 0) | (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0);
  return in;
}

// 0 when the name is unknown.
WORD VirtualKey(const std::string& raw) {
  std::string k;
  for (char c : raw) k.push_back(static_cast<char>(tolower(static_cast<unsigned char>(c))));
  struct Named { const char* name; WORD vk; };
  static const Named kNamed[] = {
      {"ctrl", VK_CONTROL}, {"control", VK_CONTROL}, {"cmd", VK_CONTROL}, {"command", VK_CONTROL},
      {"alt", VK_MENU}, {"option", VK_MENU}, {"shift", VK_SHIFT},
      {"win", VK_LWIN}, {"meta", VK_LWIN}, {"super", VK_LWIN},
      {"enter", VK_RETURN}, {"return", VK_RETURN}, {"tab", VK_TAB},
      {"esc", VK_ESCAPE}, {"escape", VK_ESCAPE}, {"space", VK_SPACE},
      {"backspace", VK_BACK}, {"delete", VK_DELETE}, {"del", VK_DELETE}, {"insert", VK_INSERT},
      {"up", VK_UP}, {"down", VK_DOWN}, {"left", VK_LEFT}, {"right", VK_RIGHT},
      {"arrowup", VK_UP}, {"arrowdown", VK_DOWN}, {"arrowleft", VK_LEFT}, {"arrowright", VK_RIGHT},
      {"home", VK_HOME}, {"end", VK_END}, {"pageup", VK_PRIOR}, {"pagedown", VK_NEXT},
  };
  for (const auto& n : kNamed) {
    if (k == n.name) return n.vk;
  }
  if (k.size() >= 2 && k[0] == 'f') {
    const int n = atoi(k.c_str() + 1);
    if (n >= 1 && n <= 24) return static_cast<WORD>(VK_F1 + n - 1);
  }
  if (k.size() == 1) {
    const char c = k[0];
    if ((c >= 'a' && c <= 'z')) return static_cast<WORD>(toupper(c));
    if (c >= '0' && c <= '9') return static_cast<WORD>(c);
    const SHORT scan = VkKeyScanW(static_cast<wchar_t>(c));
    if (scan != -1) return static_cast<WORD>(scan & 0xFF);
  }
  return 0;
}

bool IsModifier(WORD vk) { return vk == VK_CONTROL || vk == VK_MENU || vk == VK_SHIFT || vk == VK_LWIN; }

}  // namespace

bool SottoMouseMove(int x, int y) { return SetCursorPos(x, y) != FALSE; }

bool SottoMouseClick(int x, int y, int button, int count) {
  if (!SetCursorPos(x, y)) return false;
  const DWORD down = button == 1 ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
  const DWORD up = button == 1 ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;
  std::vector<INPUT> inputs;
  for (int i = 0; i < (count == 2 ? 2 : 1); ++i) {
    inputs.push_back(Mouse(down));
    inputs.push_back(Mouse(up));
  }
  Send(inputs);
  return true;
}

bool SottoMouseScroll(int x, int y, bool at_point, int dx, int dy) {
  if (at_point && !SetCursorPos(x, y)) return false;
  std::vector<INPUT> inputs;
  if (dy != 0) inputs.push_back(Mouse(MOUSEEVENTF_WHEEL, static_cast<DWORD>(-dy * WHEEL_DELTA)));
  if (dx != 0) inputs.push_back(Mouse(MOUSEEVENTF_HWHEEL, static_cast<DWORD>(dx * WHEEL_DELTA)));
  Send(inputs);
  return true;
}

bool SottoTypeText(const wchar_t* text) {
  std::vector<INPUT> inputs;
  for (const wchar_t* p = text; *p != L'\0'; ++p) {
    if (*p == L'\r') continue;
    if (*p == L'\n') {
      inputs.push_back(Key(VK_RETURN, false));
      inputs.push_back(Key(VK_RETURN, true));
      continue;
    }
    INPUT down{};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = *p;  // UTF-16 code unit; surrogate pairs go through as two
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags |= KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  Send(inputs);
  return true;
}

bool SottoPressKeys(const char* const* keys, int count) {
  std::vector<WORD> mods, rest;
  for (int i = 0; i < count; ++i) {
    const WORD vk = VirtualKey(keys[i]);
    if (vk == 0) return false;
    (IsModifier(vk) ? mods : rest).push_back(vk);
  }
  std::vector<INPUT> inputs;
  for (WORD vk : mods) inputs.push_back(Key(vk, false));
  for (WORD vk : rest) inputs.push_back(Key(vk, false));
  for (auto it = rest.rbegin(); it != rest.rend(); ++it) inputs.push_back(Key(*it, true));
  for (auto it = mods.rbegin(); it != mods.rend(); ++it) inputs.push_back(Key(*it, true));
  Send(inputs);
  return true;
}

void SottoReleaseAll() {
  std::vector<INPUT> inputs;
  for (WORD vk : {VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN, VK_RWIN}) {
    if (GetAsyncKeyState(vk) & 0x8000) inputs.push_back(Key(vk, true));
  }
  if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) inputs.push_back(Mouse(MOUSEEVENTF_LEFTUP));
  if (GetAsyncKeyState(VK_RBUTTON) & 0x8000) inputs.push_back(Mouse(MOUSEEVENTF_RIGHTUP));
  Send(inputs);
}

bool SottoFocusedElement(bool* is_password, wchar_t* name, int name_len, wchar_t* role, int role_len) {
  *is_password = false;
  if (name_len > 0) name[0] = L'\0';
  if (role_len > 0) role[0] = L'\0';
  try {
    winrt::com_ptr<IUIAutomation> automation;
    winrt::check_hresult(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                                          __uuidof(IUIAutomation), automation.put_void()));
    winrt::com_ptr<IUIAutomationElement> focused;
    winrt::check_hresult(automation->GetFocusedElement(focused.put()));
    if (!focused) return false;
    BOOL password = FALSE;
    focused->get_CurrentIsPassword(&password);
    *is_password = password != FALSE;
    BSTR text = nullptr;
    if (SUCCEEDED(focused->get_CurrentName(&text)) && text != nullptr) {
      wcsncpy_s(name, name_len, text, _TRUNCATE);
      SysFreeString(text);
    }
    text = nullptr;
    if (SUCCEEDED(focused->get_CurrentLocalizedControlType(&text)) && text != nullptr) {
      wcsncpy_s(role, role_len, text, _TRUNCATE);
      SysFreeString(text);
    }
    return true;
  } catch (...) {
    return false;
  }
}
