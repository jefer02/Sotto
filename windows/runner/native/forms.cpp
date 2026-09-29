#include "forms.h"

#include <ole2.h>
#include <oleauto.h>
#include <uiautomation.h>

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

std::string Utf8(const wchar_t* wide, int len = -1) {
  if (wide == nullptr) return std::string();
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, len, nullptr, 0, nullptr, nullptr);
  if (n <= 0) return std::string();
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, len, out.data(), n, nullptr, nullptr);
  if (len == -1 && !out.empty() && out.back() == '\0') out.pop_back();
  return out;
}

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
  if (SUCCEEDED(e->GetCachedPropertyValue(prop, &v)) && v.vt == VT_BSTR && v.bstrVal != nullptr) {
    out = Utf8(v.bstrVal, static_cast<int>(SysStringLen(v.bstrVal)));
  }
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

    com_ptr<IUIAutomationCacheRequest> cache;
    winrt::check_hresult(automation->CreateCacheRequest(cache.put()));
    for (PROPERTYID p : {UIA_ControlTypePropertyId, UIA_NamePropertyId, UIA_BoundingRectanglePropertyId,
                         UIA_IsPasswordPropertyId, UIA_IsEnabledPropertyId, UIA_IsOffscreenPropertyId,
                         UIA_IsValuePatternAvailablePropertyId, UIA_IsTogglePatternAvailablePropertyId,
                         UIA_IsSelectionItemPatternAvailablePropertyId,
                         UIA_IsExpandCollapsePatternAvailablePropertyId, UIA_IsInvokePatternAvailablePropertyId,
                         UIA_IsScrollItemPatternAvailablePropertyId, UIA_IsSelectionPatternAvailablePropertyId,
                         UIA_ValueValuePropertyId, UIA_ValueIsReadOnlyPropertyId, UIA_ToggleToggleStatePropertyId,
                         UIA_SelectionItemIsSelectedPropertyId, UIA_IsKeyboardFocusablePropertyId}) {
      cache->AddProperty(p);
    }

    // The controls a questionnaire is made of.
    std::vector<com_ptr<IUIAutomationCondition>> types;
    for (CONTROLTYPEID t : {UIA_EditControlTypeId, UIA_DocumentControlTypeId, UIA_RadioButtonControlTypeId,
                            UIA_CheckBoxControlTypeId, UIA_ComboBoxControlTypeId, UIA_ListControlTypeId,
                            UIA_ListItemControlTypeId, UIA_ButtonControlTypeId, UIA_GroupControlTypeId}) {
      VARIANT v;
      VariantInit(&v);
      v.vt = VT_I4;
      v.lVal = t;
      com_ptr<IUIAutomationCondition> c;
      winrt::check_hresult(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, v, c.put()));
      types.push_back(c);
    }
    std::vector<IUIAutomationCondition*> raw;
    for (auto& c : types) raw.push_back(c.get());
    com_ptr<IUIAutomationCondition> any;
    winrt::check_hresult(automation->CreateOrConditionFromNativeArray(raw.data(), static_cast<int>(raw.size()), any.put()));

    com_ptr<IUIAutomationElementArray> found;
    winrt::check_hresult(root->FindAllBuildCache(TreeScope_Descendants, any.get(), cache.get(), found.put()));
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

    std::string out = "[";
    bool first = true;
    for (auto& [id, e] : list) {
      const CONTROLTYPEID type = CachedInt(e.get(), UIA_ControlTypePropertyId, 0);
      const char* type_name = TypeName(type);
      if (type_name == nullptr) continue;

      std::string parent;
      if (walker && type != UIA_ButtonControlTypeId && type != UIA_DocumentControlTypeId) {
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

      VARIANT rect;
      VariantInit(&rect);
      double b[4] = {0, 0, 0, 0};
      if (SUCCEEDED(e->GetCachedPropertyValue(UIA_BoundingRectanglePropertyId, &rect)) &&
          rect.vt == (VT_R8 | VT_ARRAY) && rect.parray != nullptr) {
        double* data = nullptr;
        if (SUCCEEDED(SafeArrayAccessData(rect.parray, reinterpret_cast<void**>(&data)))) {
          for (int k = 0; k < 4; ++k) b[k] = data[k];
          SafeArrayUnaccessData(rect.parray);
        }
      }
      VariantClear(&rect);

      std::vector<std::string> patterns;
      if (CachedBool(e.get(), UIA_IsValuePatternAvailablePropertyId)) patterns.push_back("value");
      if (CachedBool(e.get(), UIA_IsTogglePatternAvailablePropertyId)) patterns.push_back("toggle");
      if (CachedBool(e.get(), UIA_IsSelectionItemPatternAvailablePropertyId)) patterns.push_back("select");
      if (CachedBool(e.get(), UIA_IsSelectionPatternAvailablePropertyId)) patterns.push_back("select");
      if (CachedBool(e.get(), UIA_IsExpandCollapsePatternAvailablePropertyId)) patterns.push_back("expand");
      if (CachedBool(e.get(), UIA_IsInvokePatternAvailablePropertyId)) patterns.push_back("invoke");
      if (CachedBool(e.get(), UIA_IsScrollItemPatternAvailablePropertyId)) patterns.push_back("scroll");
      if (CachedBool(e.get(), UIA_IsKeyboardFocusablePropertyId)) patterns.push_back("focus");

      std::string checked = "null";
      if (type == UIA_CheckBoxControlTypeId) {
        checked = CachedInt(e.get(), UIA_ToggleToggleStatePropertyId, 0) == ToggleState_On ? "true" : "false";
      } else if (type == UIA_RadioButtonControlTypeId || type == UIA_ListItemControlTypeId) {
        checked = CachedBool(e.get(), UIA_SelectionItemIsSelectedPropertyId) ? "true" : "false";
      }

      // A combo box's options: its list items, if the page exposes them
      // while it is closed (browsers usually do).
      std::vector<std::string> options;
      if (type == UIA_ComboBoxControlTypeId) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = UIA_ListItemControlTypeId;
        com_ptr<IUIAutomationCondition> isItem;
        com_ptr<IUIAutomationElementArray> items;
        if (SUCCEEDED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, v, isItem.put())) &&
            SUCCEEDED(e->FindAll(TreeScope_Descendants, isItem.get(), items.put())) && items) {
          int n = 0;
          items->get_Length(&n);
          for (int k = 0; k < n && k < 200; ++k) {
            com_ptr<IUIAutomationElement> item;
            items->GetElement(k, item.put());
            BSTR name = nullptr;
            if (item && SUCCEEDED(item->get_CurrentName(&name)) && name != nullptr) {
              options.push_back(Utf8(name, static_cast<int>(SysStringLen(name))));
              SysFreeString(name);
            }
          }
        }
      }

      if (!first) out.push_back(',');
      first = false;
      out += "{\"id\":";
      JsonString(out, id);
      out += ",\"type\":";
      JsonString(out, type_name);
      out += ",\"name\":";
      JsonString(out, CachedString(e.get(), UIA_NamePropertyId));
      if (CachedBool(e.get(), UIA_IsValuePatternAvailablePropertyId)) {
        out += ",\"value\":";
        JsonString(out, CachedString(e.get(), UIA_ValueValuePropertyId));
        out += ",\"readOnly\":";
        out += CachedBool(e.get(), UIA_ValueIsReadOnlyPropertyId) ? "true" : "false";
      }
      char nums[160];
      snprintf(nums, sizeof(nums), ",\"bounds\":[%.0f,%.0f,%.0f,%.0f]", b[0], b[1], b[2], b[3]);
      out += nums;
      out += ",\"password\":";
      out += CachedBool(e.get(), UIA_IsPasswordPropertyId) ? "true" : "false";
      out += ",\"enabled\":";
      out += CachedBool(e.get(), UIA_IsEnabledPropertyId) ? "true" : "false";
      out += ",\"offscreen\":";
      out += CachedBool(e.get(), UIA_IsOffscreenPropertyId) ? "true" : "false";
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
    // Three-state boxes may need two presses.
    for (int i = 0; i < 3; ++i) {
      ToggleState state = ToggleState_Off;
      tog->get_CurrentToggleState(&state);
      if ((state == ToggleState_On) == on) return true;
      if (FAILED(tog->Toggle())) return false;
    }
    return false;
  } catch (...) {
    return false;
  }
}

bool SottoFormChoose(const char* id, const wchar_t* label) {
  try {
    auto e = Find(id);
    if (!e) return false;
    auto expand = Pattern<IUIAutomationExpandCollapsePattern>(e.get(), UIA_ExpandCollapsePatternId);
    if (expand) {
      expand->Expand();
      Sleep(180);  // let the drop-down populate
      VARIANT v;
      VariantInit(&v);
      v.vt = VT_I4;
      v.lVal = UIA_ListItemControlTypeId;
      com_ptr<IUIAutomationCondition> isItem;
      com_ptr<IUIAutomationElementArray> items;
      Automation()->CreatePropertyCondition(UIA_ControlTypePropertyId, v, isItem.put());
      e->FindAll(TreeScope_Descendants, isItem.get(), items.put());
      int n = 0;
      if (items) items->get_Length(&n);
      const std::wstring want = Lower(label);
      com_ptr<IUIAutomationElement> match;
      for (int k = 0; k < n && !match; ++k) {
        com_ptr<IUIAutomationElement> item;
        items->GetElement(k, item.put());
        BSTR name = nullptr;
        if (item && SUCCEEDED(item->get_CurrentName(&name)) && name != nullptr) {
          if (Lower(std::wstring(name, SysStringLen(name))) == want) match = item;
          SysFreeString(name);
        }
      }
      bool ok = false;
      if (match) {
        if (auto sel = Pattern<IUIAutomationSelectionItemPattern>(match.get(), UIA_SelectionItemPatternId)) {
          ok = SUCCEEDED(sel->Select());
        }
        if (!ok) {
          if (auto inv = Pattern<IUIAutomationInvokePattern>(match.get(), UIA_InvokePatternId)) ok = SUCCEEDED(inv->Invoke());
        }
      }
      ExpandCollapseState state = ExpandCollapseState_Collapsed;
      if (SUCCEEDED(expand->get_CurrentExpandCollapseState(&state)) && state != ExpandCollapseState_Collapsed) {
        expand->Collapse();
      }
      if (ok) return true;
    }
    // Editable combos take the text.
    if (auto value = Pattern<IUIAutomationValuePattern>(e.get(), UIA_ValuePatternId)) {
      BSTR b = SysAllocString(label);
      const HRESULT hr = value->SetValue(b);
      SysFreeString(b);
      return SUCCEEDED(hr);
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
