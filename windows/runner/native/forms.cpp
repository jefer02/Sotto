#include "forms.h"

#include <ole2.h>
#include <oleauto.h>
#include <uiautomation.h>

#include <cmath>
#include <cwctype>
#include <map>
#include <string>
#include <vector>

#include <winrt/base.h>

namespace {

using winrt::com_ptr;

com_ptr<IUIAutomation>& Automation() {
  static com_ptr<IUIAutomation> automation;
  if (!automation) {
    winrt::check_hresult(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                                          __uuidof(IUIAutomation), automation.put_void()));
  }
  return automation;
}

// Elements from the last read, by runtime id.
std::map<std::string, com_ptr<IUIAutomationElement>>& Elements() {
  static std::map<std::string, com_ptr<IUIAutomationElement>> elements;
  return elements;
}

// The page the last read walked: a browser's visible document, else the
// foreground window itself.
com_ptr<IUIAutomationElement>& Page() {
  static com_ptr<IUIAutomationElement> page;
  return page;
}

std::string Utf8(const wchar_t* wide, int len = -1) {
  if (wide == nullptr) return std::string();
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, len, nullptr, 0, nullptr, nullptr);
  if (n <= 0) return std::string();
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, len, out.data(), n, nullptr, nullptr);
  if (len == -1 && !out.empty() && out.back() == '\0') out.pop_back();
  return out;
}

std::string Utf8(BSTR b) { return b == nullptr ? std::string() : Utf8(b, static_cast<int>(SysStringLen(b))); }

void JsonString(std::string& out, const std::string& s) {
  out.push_back('"');
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  out.push_back('"');
}

void JsonNumber(std::string& out, double v) {
  char buf[48];
  snprintf(buf, sizeof(buf), "%.6g", std::isfinite(v) ? v : 0.0);
  out += buf;
}

std::string RuntimeId(IUIAutomationElement* e) {
  SAFEARRAY* sa = nullptr;
  if (FAILED(e->GetRuntimeId(&sa)) || sa == nullptr) return std::string();
  std::string id;
  LONG lo = 0, hi = -1;
  SafeArrayGetLBound(sa, 1, &lo);
  SafeArrayGetUBound(sa, 1, &hi);
  for (LONG i = lo; i <= hi; ++i) {
    int v = 0;
    SafeArrayGetElement(sa, &i, &v);
    if (!id.empty()) id.push_back('.');
    id += std::to_string(v);
  }
  SafeArrayDestroy(sa);
  return id;
}

std::string CachedString(IUIAutomationElement* e, PROPERTYID prop) {
  VARIANT v;
  VariantInit(&v);
  std::string out;
  if (SUCCEEDED(e->GetCachedPropertyValue(prop, &v)) && v.vt == VT_BSTR) out = Utf8(v.bstrVal);
  VariantClear(&v);
  return out;
}

bool CachedBool(IUIAutomationElement* e, PROPERTYID prop) {
  VARIANT v;
  VariantInit(&v);
  bool out = false;
  if (SUCCEEDED(e->GetCachedPropertyValue(prop, &v)) && v.vt == VT_BOOL) out = v.boolVal != VARIANT_FALSE;
  VariantClear(&v);
  return out;
}

int CachedInt(IUIAutomationElement* e, PROPERTYID prop, int fallback) {
  VARIANT v;
  VariantInit(&v);
  int out = fallback;
  if (SUCCEEDED(e->GetCachedPropertyValue(prop, &v)) && v.vt == VT_I4) out = v.lVal;
  VariantClear(&v);
  return out;
}

double CachedDouble(IUIAutomationElement* e, PROPERTYID prop, double fallback) {
  VARIANT v;
  VariantInit(&v);
  double out = fallback;
  if (SUCCEEDED(e->GetCachedPropertyValue(prop, &v)) && v.vt == VT_R8) out = v.dblVal;
  VariantClear(&v);
  return out;
}

RECT CachedRect(IUIAutomationElement* e) {
  RECT r{0, 0, 0, 0};
  VARIANT v;
  VariantInit(&v);
  if (SUCCEEDED(e->GetCachedPropertyValue(UIA_BoundingRectanglePropertyId, &v)) && v.vt == (VT_R8 | VT_ARRAY) &&
      v.parray != nullptr) {
    double* data = nullptr;
    if (SUCCEEDED(SafeArrayAccessData(v.parray, reinterpret_cast<void**>(&data)))) {
      r = {static_cast<LONG>(data[0]), static_cast<LONG>(data[1]), static_cast<LONG>(data[0] + data[2]),
           static_cast<LONG>(data[1] + data[3])};
      SafeArrayUnaccessData(v.parray);
    }
  }
  VariantClear(&v);
  return r;
}

const char* TypeName(CONTROLTYPEID t) {
  switch (t) {
    case UIA_EditControlTypeId: return "edit";
    case UIA_DocumentControlTypeId: return "document";
    case UIA_RadioButtonControlTypeId: return "radio";
    case UIA_CheckBoxControlTypeId: return "checkbox";
    case UIA_ComboBoxControlTypeId: return "combo";
    case UIA_ListControlTypeId: return "list";
    case UIA_ListItemControlTypeId: return "listitem";
    case UIA_ButtonControlTypeId: return "button";
    case UIA_GroupControlTypeId: return "group";
    case UIA_SliderControlTypeId: return "slider";
    case UIA_SpinnerControlTypeId: return "spinner";
    case UIA_TextControlTypeId: return "text";
    default: return nullptr;
  }
}

com_ptr<IUIAutomationElement> Find(const char* id) {
  auto& all = Elements();
  auto it = all.find(id == nullptr ? std::string() : std::string(id));
  return it == all.end() ? nullptr : it->second;
}

template <typename T>
com_ptr<T> Pattern(IUIAutomationElement* e, PATTERNID id) {
  com_ptr<T> p;
  e->GetCurrentPatternAs(id, __uuidof(T), p.put_void());
  return p;
}

std::wstring Lower(std::wstring s) {
  for (auto& c : s) c = static_cast<wchar_t>(towlower(c));
  return s;
}

std::wstring Trim(const std::wstring& s) {
  size_t a = 0, b = s.size();
  while (a < b && iswspace(s[a])) ++a;
  while (b > a && iswspace(s[b - 1])) --b;
  return s.substr(a, b - a);
}

com_ptr<IUIAutomationCondition> TypeIs(CONTROLTYPEID t) {
  VARIANT v;
  VariantInit(&v);
  v.vt = VT_I4;
  v.lVal = t;
  com_ptr<IUIAutomationCondition> c;
  winrt::check_hresult(Automation()->CreatePropertyCondition(UIA_ControlTypePropertyId, v, c.put()));
  return c;
}

com_ptr<IUIAutomationCondition> AnyType(std::initializer_list<CONTROLTYPEID> types) {
  std::vector<com_ptr<IUIAutomationCondition>> held;
  std::vector<IUIAutomationCondition*> raw;
  for (CONTROLTYPEID t : types) {
    held.push_back(TypeIs(t));
    raw.push_back(held.back().get());
  }
  com_ptr<IUIAutomationCondition> any;
  winrt::check_hresult(
      Automation()->CreateOrConditionFromNativeArray(raw.data(), static_cast<int>(raw.size()), any.put()));
  return any;
}

// ───────────────────────────── The page ─────────────────────────────

std::wstring ClassName(HWND h) {
  wchar_t c[128] = {};
  GetClassNameW(h, c, 128);
  return c;
}

// Chromium (Chrome, Edge, Electron) and Firefox top-level windows.
bool IsBrowser(HWND h) {
  const std::wstring c = ClassName(h);
  return c == L"Chrome_WidgetWin_1" || c == L"MozillaWindowClass";
}

BOOL CALLBACK PokeChild(HWND child, LPARAM) {
  const std::wstring c = ClassName(child);
  if (c == L"Chrome_RenderWidgetHostHWND" || c == L"MozillaWindowClass") {
    DWORD_PTR r = 0;
    SendMessageTimeoutW(child, WM_GETOBJECT, 0, static_cast<LPARAM>(UiaRootObjectId), SMTO_ABORTIFHUNG, 200, &r);
    SendMessageTimeoutW(child, WM_GETOBJECT, 0, static_cast<LPARAM>(OBJID_CLIENT), SMTO_ABORTIFHUNG, 200, &r);
  }
  return TRUE;
}

// Chromium builds a page's accessibility tree only once an accessibility
// client asks its render widget for it; until then the window shows just
// the browser's own controls. Asking it directly switches it on.
void WarmUp(HWND fg) { EnumChildWindows(fg, PokeChild, 0); }

// The page the user is looking at: of the documents in the window, the
// largest visible one (other tabs' documents are offscreen). Null outside
// browsers, or while the page's tree isn't built yet.
com_ptr<IUIAutomationElement> VisibleDocument(IUIAutomationElement* root) {
  com_ptr<IUIAutomationCacheRequest> cache;
  winrt::check_hresult(Automation()->CreateCacheRequest(cache.put()));
  cache->AddProperty(UIA_BoundingRectanglePropertyId);
  cache->AddProperty(UIA_IsOffscreenPropertyId);
  com_ptr<IUIAutomationElementArray> docs;
  if (FAILED(root->FindAllBuildCache(TreeScope_Descendants, TypeIs(UIA_DocumentControlTypeId).get(), cache.get(),
                                     docs.put())) ||
      !docs) {
    return nullptr;
  }
  int n = 0;
  docs->get_Length(&n);
  com_ptr<IUIAutomationElement> best;
  long long best_area = 0;
  for (int i = 0; i < n; ++i) {
    com_ptr<IUIAutomationElement> d;
    if (FAILED(docs->GetElement(i, d.put())) || !d || CachedBool(d.get(), UIA_IsOffscreenPropertyId)) continue;
    const RECT r = CachedRect(d.get());
    const long long area = static_cast<long long>(r.right - r.left) * (r.bottom - r.top);
    if (area > best_area) {
      best_area = area;
      best = d;
    }
  }
  return best;
}

// Whether the page has anything a form is made of yet.
bool HasControls(IUIAutomationElement* page) {
  com_ptr<IUIAutomationElement> first;
  const auto c = AnyType({UIA_EditControlTypeId, UIA_RadioButtonControlTypeId, UIA_CheckBoxControlTypeId,
                          UIA_ComboBoxControlTypeId, UIA_SliderControlTypeId, UIA_SpinnerControlTypeId,
                          UIA_ButtonControlTypeId});
  return SUCCEEDED(page->FindFirst(TreeScope_Descendants, c.get(), first.put())) && first;
}

// The nearest ancestor (or [e] itself) that scrolls vertically; else the
// page.
com_ptr<IUIAutomationScrollPattern> ScrollerFor(IUIAutomationElement* e) {
  // The raw view: a scrolling panel is often a plain <div>, which the
  // control view leaves out.
  com_ptr<IUIAutomationTreeWalker> walker;
  Automation()->get_RawViewWalker(walker.put());
  com_ptr<IUIAutomationElement> at;
  at.copy_from(e);
  for (int depth = 0; at && walker && depth < 40; ++depth) {
    if (auto s = Pattern<IUIAutomationScrollPattern>(at.get(), UIA_ScrollPatternId)) {
      BOOL vertical = FALSE;
      if (SUCCEEDED(s->get_CurrentVerticallyScrollable(&vertical)) && vertical) return s;
    }
    com_ptr<IUIAutomationElement> up;
    walker->GetParentElement(at.get(), up.put());
    at = up;
  }
  if (Page()) {
    if (auto s = Pattern<IUIAutomationScrollPattern>(Page().get(), UIA_ScrollPatternId)) {
      BOOL vertical = FALSE;
      if (SUCCEEDED(s->get_CurrentVerticallyScrollable(&vertical)) && vertical) return s;
    }
  }
  return nullptr;
}

std::string CurrentName(IUIAutomationElement* e) {
  BSTR b = nullptr;
  std::string out;
  if (e != nullptr && SUCCEEDED(e->get_CurrentName(&b))) out = Utf8(b);
  SysFreeString(b);
  return out;
}

// An option named [want] (case aside; then a prefix either way) among [items].
com_ptr<IUIAutomationElement> MatchItem(IUIAutomationElementArray* items, const std::wstring& want,
                                        bool skip_offscreen) {
  if (items == nullptr) return nullptr;
  int n = 0;
  items->get_Length(&n);
  com_ptr<IUIAutomationElement> prefix;
  for (int k = 0; k < n && k < 400; ++k) {
    com_ptr<IUIAutomationElement> item;
    items->GetElement(k, item.put());
    if (!item) continue;
    if (skip_offscreen) {
      BOOL off = FALSE;
      if (SUCCEEDED(item->get_CurrentIsOffscreen(&off)) && off) continue;
    }
    BSTR name = nullptr;
    if (FAILED(item->get_CurrentName(&name)) || name == nullptr) continue;
    const std::wstring got = Lower(Trim(std::wstring(name, SysStringLen(name))));
    SysFreeString(name);
    if (got.empty()) continue;
    if (got == want) return item;
    if (!prefix && (got.rfind(want, 0) == 0 || want.rfind(got, 0) == 0)) prefix = item;
  }
  return prefix;
}

// Whether [combo] now shows [want] (when it can show anything: a combo
// without ValuePattern can't tell, and counts as done).
bool Shows(IUIAutomationElement* combo, const std::wstring& want) {
  auto v = Pattern<IUIAutomationValuePattern>(combo, UIA_ValuePatternId);
  if (!v) return true;
  for (int wait = 0; wait < 8; ++wait) {
    BSTR b = nullptr;
    if (SUCCEEDED(v->get_CurrentValue(&b)) && b != nullptr) {
      const std::wstring now = Lower(Trim(std::wstring(b, SysStringLen(b))));
      SysFreeString(b);
      if (!now.empty() && (now.find(want) != std::wstring::npos || want.find(now) != std::wstring::npos)) return true;
    }
    Sleep(40);
  }
  return false;
}

// Picks [item] for [combo]. A custom popup's option reacts to a click
// (Invoke), a native list's to selection — except Firefox's, which only
// highlights a selected option: what the combo shows decides.
bool Pick(IUIAutomationElement* combo, IUIAutomationElement* item, const std::wstring& want, bool click_first) {
  auto invoke = [&] {
    auto inv = Pattern<IUIAutomationInvokePattern>(item, UIA_InvokePatternId);
    return inv && SUCCEEDED(inv->Invoke());
  };
  auto select = [&] {
    auto sel = Pattern<IUIAutomationSelectionItemPattern>(item, UIA_SelectionItemPatternId);
    return sel && SUCCEEDED(sel->Select());
  };
  if ((click_first ? invoke() : select()) && Shows(combo, want)) return true;
  return (click_first ? select() : invoke()) && Shows(combo, want);
}

}  // namespace

bool SottoFormRead(int max_elements, char** json, const char** error) {
  *json = nullptr;
  *error = "";
  try {
    HWND fg = GetForegroundWindow();
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (fg == nullptr) {
      *error = "no_window";
      return false;
    }
    if (pid == GetCurrentProcessId()) {
      *error = "own_window";
      return false;
    }
    auto& automation = Automation();
    com_ptr<IUIAutomationElement> root;
    winrt::check_hresult(automation->ElementFromHandle(fg, root.put()));

    // A browser: read its page only — never its address bar, tabs or
    // translation bubble — waking the page's tree first if it's asleep.
    com_ptr<IUIAutomationElement> scope = root;
    if (IsBrowser(fg)) {
      com_ptr<IUIAutomationElement> doc = VisibleDocument(root.get());
      for (int attempt = 0; attempt < 4 && (!doc || !HasControls(doc.get())); ++attempt) {
        WarmUp(fg);
        Sleep(attempt == 0 ? 150 : 300);
        doc = VisibleDocument(root.get());
      }
      if (doc) scope = doc;
    }
    Page() = scope;

    com_ptr<IUIAutomationCacheRequest> cache;
    winrt::check_hresult(automation->CreateCacheRequest(cache.put()));
    for (PROPERTYID p : {UIA_ControlTypePropertyId, UIA_NamePropertyId, UIA_BoundingRectanglePropertyId,
                         UIA_IsPasswordPropertyId, UIA_IsEnabledPropertyId, UIA_IsOffscreenPropertyId,
                         UIA_IsValuePatternAvailablePropertyId, UIA_IsTogglePatternAvailablePropertyId,
                         UIA_IsSelectionItemPatternAvailablePropertyId,
                         UIA_IsExpandCollapsePatternAvailablePropertyId, UIA_IsInvokePatternAvailablePropertyId,
                         UIA_IsScrollItemPatternAvailablePropertyId, UIA_IsSelectionPatternAvailablePropertyId,
                         UIA_IsRangeValuePatternAvailablePropertyId, UIA_ValueValuePropertyId,
                         UIA_ValueIsReadOnlyPropertyId, UIA_ToggleToggleStatePropertyId,
                         UIA_SelectionItemIsSelectedPropertyId, UIA_IsKeyboardFocusablePropertyId,
                         UIA_RangeValueValuePropertyId, UIA_RangeValueMinimumPropertyId,
                         UIA_RangeValueMaximumPropertyId, UIA_RangeValueSmallChangePropertyId,
                         UIA_RangeValueIsReadOnlyPropertyId, UIA_HelpTextPropertyId, UIA_FullDescriptionPropertyId,
                         UIA_LabeledByPropertyId, UIA_AutomationIdPropertyId}) {
      cache->AddProperty(p);
    }

    // The controls a questionnaire is made of, and the text around them
    // (questions are often plain text or a heading above an unlabelled box).
    const auto any = AnyType({UIA_EditControlTypeId, UIA_DocumentControlTypeId, UIA_RadioButtonControlTypeId,
                              UIA_CheckBoxControlTypeId, UIA_ComboBoxControlTypeId, UIA_ListControlTypeId,
                              UIA_ListItemControlTypeId, UIA_ButtonControlTypeId, UIA_GroupControlTypeId,
                              UIA_SliderControlTypeId, UIA_SpinnerControlTypeId, UIA_TextControlTypeId});

    com_ptr<IUIAutomationElementArray> found;
    winrt::check_hresult(scope->FindAllBuildCache(TreeScope_Descendants, any.get(), cache.get(), found.put()));
    int count = 0;
    if (found) found->get_Length(&count);

    // Parents: the nearest ancestor (control view) that we collected too, so
    // radios group by their radiogroup / fieldset even through wrapper panes.
    com_ptr<IUIAutomationTreeWalker> walker;
    automation->get_ControlViewWalker(walker.put());

    auto& elements = Elements();
    elements.clear();
    std::vector<std::pair<std::string, com_ptr<IUIAutomationElement>>> list;
    for (int i = 0; i < count && static_cast<int>(list.size()) < max_elements; ++i) {
      com_ptr<IUIAutomationElement> e;
      if (FAILED(found->GetElement(i, e.put())) || !e) continue;
      std::string id = RuntimeId(e.get());
      if (id.empty()) continue;
      elements[id] = e;
      list.emplace_back(id, e);
    }

    // First, the area that was read: the page (or the window).
    std::string out = "[";
    bool first = true;
    {
      RECT page{};
      if (SUCCEEDED(scope->get_CurrentBoundingRectangle(&page)) && page.right > page.left) {
        char nums[160];
        snprintf(nums, sizeof(nums), "{\"id\":\"page\",\"type\":\"page\",\"bounds\":[%ld,%ld,%ld,%ld]}", page.left,
                 page.top, page.right - page.left, page.bottom - page.top);
        out += nums;
        first = false;
      }
    }
    for (auto& [id, e] : list) {
      const CONTROLTYPEID type = CachedInt(e.get(), UIA_ControlTypePropertyId, 0);
      const char* type_name = TypeName(type);
      if (type_name == nullptr) continue;
      const std::string name = CachedString(e.get(), UIA_NamePropertyId);
      const RECT r = CachedRect(e.get());
      // Plain text: only what could be a question — something to read,
      // with a place on the page.
      if (type == UIA_TextControlTypeId && (name.empty() || name.size() > 400 || r.right <= r.left)) continue;

      std::string parent;
      if (walker && type != UIA_ButtonControlTypeId && type != UIA_DocumentControlTypeId &&
          type != UIA_TextControlTypeId) {
        com_ptr<IUIAutomationElement> p;
        walker->GetParentElement(e.get(), p.put());
        for (int depth = 0; p && depth < 4; ++depth) {
          std::string pid_str = RuntimeId(p.get());
          if (elements.count(pid_str) != 0) {
            parent = pid_str;
            break;
          }
          com_ptr<IUIAutomationElement> up;
          walker->GetParentElement(p.get(), up.put());
          p = up;
        }
      }

      if (!first) out.push_back(',');
      first = false;
      out += "{\"id\":";
      JsonString(out, id);
      out += ",\"type\":";
      JsonString(out, type_name);
      out += ",\"name\":";
      JsonString(out, name);
      char nums[160];
      snprintf(nums, sizeof(nums), ",\"bounds\":[%ld,%ld,%ld,%ld]", r.left, r.top, r.right - r.left,
               r.bottom - r.top);
      out += nums;
      out += ",\"offscreen\":";
      out += CachedBool(e.get(), UIA_IsOffscreenPropertyId) ? "true" : "false";
      if (type == UIA_TextControlTypeId) {
        out += "}";
        continue;
      }

      std::vector<std::string> patterns;
      const bool has_value = CachedBool(e.get(), UIA_IsValuePatternAvailablePropertyId);
      const bool has_range = CachedBool(e.get(), UIA_IsRangeValuePatternAvailablePropertyId);
      if (has_value) patterns.push_back("value");
      if (CachedBool(e.get(), UIA_IsTogglePatternAvailablePropertyId)) patterns.push_back("toggle");
      if (CachedBool(e.get(), UIA_IsSelectionItemPatternAvailablePropertyId)) patterns.push_back("select");
      if (CachedBool(e.get(), UIA_IsSelectionPatternAvailablePropertyId)) patterns.push_back("select");
      if (CachedBool(e.get(), UIA_IsExpandCollapsePatternAvailablePropertyId)) patterns.push_back("expand");
      if (CachedBool(e.get(), UIA_IsInvokePatternAvailablePropertyId)) patterns.push_back("invoke");
      if (CachedBool(e.get(), UIA_IsScrollItemPatternAvailablePropertyId)) patterns.push_back("scroll");
      if (CachedBool(e.get(), UIA_IsKeyboardFocusablePropertyId)) patterns.push_back("focus");
      if (has_range) patterns.push_back("range");

      std::string checked = "null";
      if (type == UIA_CheckBoxControlTypeId) {
        checked = CachedInt(e.get(), UIA_ToggleToggleStatePropertyId, 0) == ToggleState_On ? "true" : "false";
      } else if (type == UIA_RadioButtonControlTypeId || type == UIA_ListItemControlTypeId) {
        checked = CachedBool(e.get(), UIA_SelectionItemIsSelectedPropertyId) ? "true" : "false";
      }

      // A combo box's options: its list items, if the page exposes them
      // while it is closed (native selects usually do).
      std::vector<std::string> options;
      if (type == UIA_ComboBoxControlTypeId) {
        com_ptr<IUIAutomationElementArray> items;
        if (SUCCEEDED(e->FindAll(TreeScope_Descendants, TypeIs(UIA_ListItemControlTypeId).get(), items.put())) &&
            items) {
          int n = 0;
          items->get_Length(&n);
          for (int k = 0; k < n && k < 200; ++k) {
            com_ptr<IUIAutomationElement> item;
            items->GetElement(k, item.put());
            if (item) options.push_back(CurrentName(item.get()));
          }
        }
      }

      // What labels it besides its name: aria-labelledby / <label for>, the
      // help text and the description (aria-describedby, placeholder).
      std::string labeled_by;
      {
        com_ptr<IUIAutomationElement> label;
        if (SUCCEEDED(e->get_CachedLabeledBy(label.put())) && label) labeled_by = CurrentName(label.get());
      }
      const std::string help = CachedString(e.get(), UIA_HelpTextPropertyId);
      const std::string description = CachedString(e.get(), UIA_FullDescriptionPropertyId);

      if (has_value) {
        out += ",\"value\":";
        JsonString(out, CachedString(e.get(), UIA_ValueValuePropertyId));
        out += ",\"readOnly\":";
        out += CachedBool(e.get(), UIA_ValueIsReadOnlyPropertyId) ? "true" : "false";
      }
      if (has_range) {
        out += ",\"range\":[";
        JsonNumber(out, CachedDouble(e.get(), UIA_RangeValueMinimumPropertyId, 0));
        out.push_back(',');
        JsonNumber(out, CachedDouble(e.get(), UIA_RangeValueMaximumPropertyId, 0));
        out.push_back(',');
        JsonNumber(out, CachedDouble(e.get(), UIA_RangeValueValuePropertyId, 0));
        out.push_back(',');
        JsonNumber(out, CachedDouble(e.get(), UIA_RangeValueSmallChangePropertyId, 0));
        out += "]";
        if (!has_value) {
          out += ",\"readOnly\":";
          out += CachedBool(e.get(), UIA_RangeValueIsReadOnlyPropertyId) ? "true" : "false";
        }
      }
      if (!labeled_by.empty() && labeled_by != name) {
        out += ",\"labeledBy\":";
        JsonString(out, labeled_by);
      }
      if (!help.empty()) {
        out += ",\"help\":";
        JsonString(out, help);
      }
      if (!description.empty() && description != help) {
        out += ",\"description\":";
        JsonString(out, description);
      }
      out += ",\"password\":";
      out += CachedBool(e.get(), UIA_IsPasswordPropertyId) ? "true" : "false";
      out += ",\"enabled\":";
      out += CachedBool(e.get(), UIA_IsEnabledPropertyId) ? "true" : "false";
      out += ",\"checked\":" + checked;
      if (!parent.empty()) {
        out += ",\"parent\":";
        JsonString(out, parent);
      }
      out += ",\"patterns\":[";
      for (size_t k = 0; k < patterns.size(); ++k) {
        if (k > 0) out.push_back(',');
        JsonString(out, patterns[k]);
      }
      out += "]";
      if (!options.empty()) {
        out += ",\"options\":[";
        for (size_t k = 0; k < options.size(); ++k) {
          if (k > 0) out.push_back(',');
          JsonString(out, options[k]);
        }
        out += "]";
      }
      out += "}";
    }
    out += "]";
    *json = static_cast<char*>(malloc(out.size() + 1));
    memcpy(*json, out.c_str(), out.size() + 1);
    return true;
  } catch (...) {
    *error = "uia_failed";
    return false;
  }
}

void SottoFormFree(char* json) { free(json); }

bool SottoFormSetValue(const char* id, const wchar_t* text) {
  try {
    auto e = Find(id);
    if (!e) return false;
    auto value = Pattern<IUIAutomationValuePattern>(e.get(), UIA_ValuePatternId);
    if (!value) return false;
    e->SetFocus();
    BSTR b = SysAllocString(text);
    const HRESULT hr = value->SetValue(b);
    SysFreeString(b);
    return SUCCEEDED(hr);
  } catch (...) {
    return false;
  }
}

bool SottoFormSetRange(const char* id, double value) {
  try {
    auto e = Find(id);
    if (!e) return false;
    // Custom (ARIA) sliders accept this and ignore it; the caller reads the
    // value back a moment later to tell.
    if (auto range = Pattern<IUIAutomationRangeValuePattern>(e.get(), UIA_RangeValuePatternId)) {
      if (SUCCEEDED(range->SetValue(value))) return true;
    }
    // A number box takes the digits.
    if (auto v = Pattern<IUIAutomationValuePattern>(e.get(), UIA_ValuePatternId)) {
      wchar_t text[64];
      swprintf(text, 64, L"%.10g", value);
      BSTR b = SysAllocString(text);
      const HRESULT hr = v->SetValue(b);
      SysFreeString(b);
      return SUCCEEDED(hr);
    }
    return false;
  } catch (...) {
    return false;
  }
}

bool SottoFormSelect(const char* id) {
  try {
    auto e = Find(id);
    if (!e) return false;
    if (auto sel = Pattern<IUIAutomationSelectionItemPattern>(e.get(), UIA_SelectionItemPatternId)) {
      if (SUCCEEDED(sel->Select())) return true;
    }
    if (auto inv = Pattern<IUIAutomationInvokePattern>(e.get(), UIA_InvokePatternId)) {
      return SUCCEEDED(inv->Invoke());
    }
    if (auto tog = Pattern<IUIAutomationTogglePattern>(e.get(), UIA_TogglePatternId)) {
      return SUCCEEDED(tog->Toggle());
    }
    return false;
  } catch (...) {
    return false;
  }
}

bool SottoFormToggle(const char* id, bool on) {
  try {
    auto e = Find(id);
    if (!e) return false;
    auto tog = Pattern<IUIAutomationTogglePattern>(e.get(), UIA_TogglePatternId);
    if (!tog) {
      auto inv = Pattern<IUIAutomationInvokePattern>(e.get(), UIA_InvokePatternId);
      return inv && SUCCEEDED(inv->Invoke());
    }
    // Three-state boxes may need two presses. Chromium applies a toggle a
    // moment after the call returns: wait for the state to change before
    // pressing again, or the box flips back and forth.
    ToggleState state = ToggleState_Off;
    tog->get_CurrentToggleState(&state);
    for (int i = 0; i < 3; ++i) {
      if ((state == ToggleState_On) == on) return true;
      const ToggleState before = state;
      if (FAILED(tog->Toggle())) return false;
      for (int wait = 0; wait < 12; ++wait) {
        tog->get_CurrentToggleState(&state);
        if (state != before) break;
        Sleep(25);
      }
    }
    return (state == ToggleState_On) == on;
  } catch (...) {
    return false;
  }
}

bool SottoFormChoose(const char* id, const wchar_t* label) {
  try {
    auto e = Find(id);
    if (!e) return false;
    const std::wstring want = Lower(Trim(label));
    const auto items = AnyType({UIA_ListItemControlTypeId, UIA_MenuItemControlTypeId, UIA_DataItemControlTypeId,
                                UIA_TreeItemControlTypeId});
    auto expand = Pattern<IUIAutomationExpandCollapsePattern>(e.get(), UIA_ExpandCollapsePatternId);
    bool opened = false;
    if (expand) {
      opened = SUCCEEDED(expand->Expand());
    } else if (auto inv = Pattern<IUIAutomationInvokePattern>(e.get(), UIA_InvokePatternId)) {
      opened = SUCCEEDED(inv->Invoke());
    }
    bool ok = false;
    if (opened) {
      // Let the list populate; a custom popup may take a frame or two.
      for (int wait = 0; wait < 4 && !ok; ++wait) {
        Sleep(wait == 0 ? 180 : 150);
        // 1. Inside the combo: a native <select>'s own list.
        com_ptr<IUIAutomationElementArray> own;
        e->FindAll(TreeScope_Descendants, items.get(), own.put());
        if (auto m = MatchItem(own.get(), want, false)) {
          ok = Pick(e.get(), m.get(), want, false);
          break;
        }
        // 2. The list it controls (aria-controls), wherever it sits.
        VARIANT v;
        VariantInit(&v);
        if (SUCCEEDED(e->GetCurrentPropertyValue(UIA_ControllerForPropertyId, &v)) && v.vt == VT_UNKNOWN &&
            v.punkVal != nullptr) {
          com_ptr<IUIAutomationElementArray> controlled;
          v.punkVal->QueryInterface(__uuidof(IUIAutomationElementArray), controlled.put_void());
          int n = 0;
          if (controlled) controlled->get_Length(&n);
          for (int k = 0; k < n && !ok; ++k) {
            com_ptr<IUIAutomationElement> popup;
            controlled->GetElement(k, popup.put());
            com_ptr<IUIAutomationElementArray> found;
            if (popup && SUCCEEDED(popup->FindAll(TreeScope_Descendants, items.get(), found.put()))) {
              if (auto m = MatchItem(found.get(), want, false)) ok = Pick(e.get(), m.get(), want, true);
            }
          }
        }
        VariantClear(&v);
        if (ok) break;
        // 3. Anywhere on the page: popups rendered at the end of the body.
        if (Page()) {
          com_ptr<IUIAutomationElementArray> found;
          if (SUCCEEDED(Page()->FindAll(TreeScope_Descendants, items.get(), found.put()))) {
            if (auto m = MatchItem(found.get(), want, true)) ok = Pick(e.get(), m.get(), want, true);
          }
        }
      }
      if (expand) {
        ExpandCollapseState state = ExpandCollapseState_Collapsed;
        if (SUCCEEDED(expand->get_CurrentExpandCollapseState(&state)) && state != ExpandCollapseState_Collapsed) {
          expand->Collapse();
        }
      }
      if (ok) return true;
    }
    // Editable combos take the text.
    if (auto value = Pattern<IUIAutomationValuePattern>(e.get(), UIA_ValuePatternId)) {
      BOOL read_only = TRUE;
      if (SUCCEEDED(value->get_CurrentIsReadOnly(&read_only)) && !read_only) {
        BSTR b = SysAllocString(label);
        const HRESULT hr = value->SetValue(b);
        SysFreeString(b);
        return SUCCEEDED(hr);
      }
    }
    return false;
  } catch (...) {
    return false;
  }
}

bool SottoFormInvoke(const char* id) {
  try {
    auto e = Find(id);
    if (!e) return false;
    auto inv = Pattern<IUIAutomationInvokePattern>(e.get(), UIA_InvokePatternId);
    return inv && SUCCEEDED(inv->Invoke());
  } catch (...) {
    return false;
  }
}

bool SottoFormFocus(const char* id) {
  try {
    auto e = Find(id);
    return e && SUCCEEDED(e->SetFocus());
  } catch (...) {
    return false;
  }
}

bool SottoFormState(const char* id, char** json) {
  *json = nullptr;
  try {
    auto e = Find(id);
    if (!e) return false;
    std::string out = "{\"name\":";
    JsonString(out, CurrentName(e.get()));
    if (auto v = Pattern<IUIAutomationValuePattern>(e.get(), UIA_ValuePatternId)) {
      BSTR b = nullptr;
      if (SUCCEEDED(v->get_CurrentValue(&b))) {
        out += ",\"value\":";
        JsonString(out, Utf8(b));
      }
      SysFreeString(b);
    }
    if (auto t = Pattern<IUIAutomationTogglePattern>(e.get(), UIA_TogglePatternId)) {
      ToggleState s = ToggleState_Off;
      if (SUCCEEDED(t->get_CurrentToggleState(&s))) out += s == ToggleState_On ? ",\"checked\":true" : ",\"checked\":false";
    } else if (auto s = Pattern<IUIAutomationSelectionItemPattern>(e.get(), UIA_SelectionItemPatternId)) {
      BOOL selected = FALSE;
      if (SUCCEEDED(s->get_CurrentIsSelected(&selected))) out += selected ? ",\"checked\":true" : ",\"checked\":false";
    }
    if (auto r = Pattern<IUIAutomationRangeValuePattern>(e.get(), UIA_RangeValuePatternId)) {
      double now = 0;
      if (SUCCEEDED(r->get_CurrentValue(&now))) {
        out += ",\"rangeValue\":";
        JsonNumber(out, now);
      }
    }
    out += "}";
    *json = _strdup(out.c_str());
    return *json != nullptr;
  } catch (...) {
    return false;
  }
}

bool SottoForegroundInfo(char** json) {
  *json = nullptr;
  HWND fg = GetForegroundWindow();
  if (fg == nullptr) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(fg, &pid);
  wchar_t title[512] = {};
  const int title_len = GetWindowTextW(fg, title, 512);
  std::string app;
  if (HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) {
    wchar_t path[MAX_PATH] = {};
    DWORD size = MAX_PATH;
    if (QueryFullProcessImageNameW(proc, 0, path, &size)) {
      std::wstring file(path, size);
      const size_t slash = file.find_last_of(L"\\/");
      if (slash != std::wstring::npos) file = file.substr(slash + 1);
      if (file.size() > 4 && Lower(file.substr(file.size() - 4)) == L".exe") file.resize(file.size() - 4);
      app = Utf8(file.c_str(), static_cast<int>(file.size()));
    }
    CloseHandle(proc);
  }
  std::string out = "{\"id\":\"" + std::to_string(reinterpret_cast<uintptr_t>(fg)) + "\",\"title\":";
  JsonString(out, Utf8(title, title_len));
  out += ",\"app\":";
  JsonString(out, app);
  out += pid == GetCurrentProcessId() ? ",\"own\":true}" : ",\"own\":false}";
  *json = _strdup(out.c_str());
  return *json != nullptr;
}

int SottoFormCanScrollDown(const char* anchor) {
  try {
    HWND fg = GetForegroundWindow();
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (fg == nullptr || pid == GetCurrentProcessId()) return -1;
    com_ptr<IUIAutomationScrollPattern> scroll;
    if (auto e = Find(anchor)) scroll = ScrollerFor(e.get());
    if (!scroll && Page()) scroll = ScrollerFor(Page().get());
    double percent = -1;
    if (!scroll || FAILED(scroll->get_CurrentVerticalScrollPercent(&percent)) || percent < 0) return -1;
    return percent < 99.5 ? 1 : 0;
  } catch (...) {
    return -1;
  }
}

double SottoFormScrollDown(const char* anchor) {
  try {
    com_ptr<IUIAutomationScrollPattern> scroll;
    if (auto e = Find(anchor)) scroll = ScrollerFor(e.get());
    if (!scroll && Page()) scroll = ScrollerFor(Page().get());
    if (!scroll) return -1;
    double before = -1;
    scroll->get_CurrentVerticalScrollPercent(&before);
    if (FAILED(scroll->Scroll(ScrollAmount_NoAmount, ScrollAmount_LargeIncrement))) return -1;
    // The position catches up a moment later.
    Sleep(120);
    double after = -1;
    if (FAILED(scroll->get_CurrentVerticalScrollPercent(&after))) return -1;
    return after;
  } catch (...) {
    return -1;
  }
}

bool SottoFormScrollIntoView(const char* id) {
  try {
    auto e = Find(id);
    if (!e) return false;
    auto scroll = Pattern<IUIAutomationScrollItemPattern>(e.get(), UIA_ScrollItemPatternId);
    return scroll && SUCCEEDED(scroll->ScrollIntoView());
  } catch (...) {
    return false;
  }
}
