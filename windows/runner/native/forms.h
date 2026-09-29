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

#endif  // RUNNER_NATIVE_FORMS_H_
