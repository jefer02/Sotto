#ifndef RUNNER_NATIVE_FORMS_H_
#define RUNNER_NATIVE_FORMS_H_

#include <windows.h>

// Questionnaire filling through UI Automation. Plain-C boundary, like
// input.h: the runner is built without exceptions, this file with them.
//
// SottoFormRead walks the foreground window (never Sotto's own) and returns
// a UTF-8 JSON array of form controls and the text around them; element ids
// are UIA runtime ids, valid until the next read. Every other call
// addresses those ids. In a browser only the visible page is read (not the
// address bar or other tabs), and a page whose tree isn't built yet is
// woken up first.

// Returns false with *error set (static string) when there's nothing to
// read. Free *json with SottoFormFree.
bool SottoFormRead(int max_elements, char** json, const char** error);
void SottoFormFree(char* json);

bool SottoFormSetValue(const char* id, const wchar_t* text);
// RangeValue.SetValue (sliders, spinners), else the number as text through
// ValuePattern. Custom sliders may accept it and ignore it: read it back.
bool SottoFormSetRange(const char* id, double value);
// SelectionItem.Select, else Invoke.
bool SottoFormSelect(const char* id);
// TogglePattern until the state is `on`.
bool SottoFormToggle(const char* id, bool on);
// Opens a combo box and picks the item named `label`: in its own list, in
// the list it controls (aria-controls), or in a popup anywhere on the page;
// falls back to ValuePattern for editable combos.
bool SottoFormChoose(const char* id, const wchar_t* label);
bool SottoFormInvoke(const char* id);
bool SottoFormFocus(const char* id);
bool SottoFormScrollIntoView(const char* id);

// One element's state now, as UTF-8 JSON: {"name","value"?,"checked"?,
// "rangeValue"?}. Free *json with SottoFormFree.
bool SottoFormState(const char* id, char** json);

// The foreground window as UTF-8 JSON: {"id","title","app","own"} — app is
// the process's file name without ".exe"; own is true for Sotto itself.
// Free *json with SottoFormFree.
bool SottoForegroundInfo(char** json);

// Whether the page can scroll further down — the scroll container around
// element `anchor` (the form's own panel, not a sidebar), else the page:
// 1 yes, 0 it's at the bottom, -1 can't tell (no ScrollPattern).
int SottoFormCanScrollDown(const char* anchor);

// Scrolls that container one screen down; returns its new vertical
// position (0-100), or -1 when there is nothing to scroll this way.
double SottoFormScrollDown(const char* anchor);

#endif  // RUNNER_NATIVE_FORMS_H_
