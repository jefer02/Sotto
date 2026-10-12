#ifndef RUNNER_NATIVE_FORMS_H_
#define RUNNER_NATIVE_FORMS_H_

#include <windows.h>

// Questionnaire filling through UI Automation. Plain-C boundary, like
// input.h: the runner is built without exceptions, this file with them.
//
// SottoFormRead walks the foreground window (never Sotto's own) and returns
// a UTF-8 JSON array of form controls; element ids are UIA runtime ids,
// valid until the next read. Every other call addresses those ids.

// Returns false with *error set (static string) when there's nothing to
// read. Free *json with SottoFormFree.
bool SottoFormRead(int max_elements, char** json, const char** error);
void SottoFormFree(char* json);

bool SottoFormSetValue(const char* id, const wchar_t* text);
// SelectionItem.Select, else Invoke.
bool SottoFormSelect(const char* id);
// TogglePattern until the state is `on`.
bool SottoFormToggle(const char* id, bool on);
// Opens a combo box, selects the item named `label`, closes it; falls back
// to ValuePattern for editable combos.
bool SottoFormChoose(const char* id, const wchar_t* label);
bool SottoFormInvoke(const char* id);
bool SottoFormFocus(const char* id);
bool SottoFormScrollIntoView(const char* id);

// The foreground window as UTF-8 JSON: {"id","title","app","own"} — app is
// the process's file name without ".exe"; own is true for Sotto itself.
// Free *json with SottoFormFree.
bool SottoForegroundInfo(char** json);

// Whether the foreground window's page can scroll further down: 1 yes,
// 0 it's at the bottom, -1 can't tell (no ScrollPattern).
int SottoFormCanScrollDown();

#endif  // RUNNER_NATIVE_FORMS_H_
