; Sotto installer (Inno Setup 6). Per-user: no administrator rights needed.
; Built by tool/package_windows.ps1 and the release workflow:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=<dist> windows\installer\sotto.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Never change AppId: it ties upgrades and the uninstaller to earlier installs.
AppId={{6B1E4D2A-8C3F-4E7B-9A51-2F0D7C9E4A13}
AppName=Sotto
AppVersion={#AppVersion}
AppVerName=Sotto {#AppVersion}
AppPublisher=Jeferson Manuel Morillo Vallejo
AppPublisherURL=https://github.com/jefer02/Sotto
AppSupportURL=https://github.com/jefer02/Sotto/issues
AppCopyright=Copyright (C) 2026 Jeferson Manuel Morillo Vallejo. MIT License.
DefaultDirName={localappdata}\Programs\Sotto
DefaultGroupName=Sotto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Sotto-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sotto.exe
UninstallDisplayName=Sotto
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Sotto must not be running while its files are replaced.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Sotto"; Filename: "{app}\sotto.exe"
Name: "{group}\{cm:UninstallProgram,Sotto}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Sotto"; Filename: "{app}\sotto.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sotto.exe"; Description: "{cm:LaunchProgram,Sotto}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The browser extension's native-messaging manifests Sotto writes for this user
; (lib/services/screen/host_manifest.dart). Scripts and settings are kept.
Type: files; Name: "{localappdata}\Sotto\NativeMessagingHosts\app.sotto.bridge.json"
Type: files; Name: "{localappdata}\Sotto\NativeMessagingHosts\app.sotto.bridge.firefox.json"
Type: dirifempty; Name: "{localappdata}\Sotto\NativeMessagingHosts"

[Registry]
; Sotto registers its native messaging host on every start; the uninstaller removes it.
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\app.sotto.bridge"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\app.sotto.bridge"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\app.sotto.bridge"; Flags: uninsdeletekey dontcreatekey
