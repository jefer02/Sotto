@echo off
rem Builds probe.exe next to this file: windows/runner/native/forms.cpp and
rem input.cpp (the code Sotto fills forms with) behind a small command line.
rem See probe.cpp for its commands and test/integration/form_fixture_live_test.dart
rem for the run against test/fixtures/forms. Needs Visual Studio with C++.
setlocal
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -prerelease -property installationPath`) do set VS=%%i
if not defined VS (
  echo Visual Studio not found.
  exit /b 1
)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d "%~dp0"
set NATIVE=%~dp0..\..\windows\runner\native
cl /nologo /std:c++20 /EHsc /O1 /DNOMINMAX /DWIN32_LEAN_AND_MEAN /I"%NATIVE%" probe.cpp "%NATIVE%\forms.cpp" ^
  "%NATIVE%\input.cpp" "%NATIVE%\screen_capture.cpp" /Fe:probe.exe /Fo:%TEMP%\ ole32.lib oleaut32.lib uiautomationcore.lib windowsapp.lib user32.lib d3d11.lib dxgi.lib windowscodecs.lib shcore.lib gdi32.lib
