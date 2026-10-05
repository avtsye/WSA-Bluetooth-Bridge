; WSA Bluetooth Bridge installer
#define MyAppName "WSA Bluetooth Bridge"
#define MyAppVersion "0.4.0"
#define MyAppPublisher "avtsye"
#define MyAppExeName "WsaBluetoothHost.exe"

[Setup]
AppId={{8CBDA1BD-E9A3-41C5-B83E-0D71378C41D8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\WSA Bluetooth Bridge
DefaultGroupName={#MyAppName}
OutputDir=..\artifacts\installer
OutputBaseFilename=WSA-Bluetooth-Bridge-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupLogging=yes

[Files]
Source: "..\artifacts\windows-host-lite\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\artifacts\wsa-system-module.zip"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-WsaSystem.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\WSA Bluetooth Bridge"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\WSA Bluetooth Bridge"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "צור קיצור דרך בשולחן העבודה"; GroupDescription: "קיצורי דרך:"
Name: "autostart"; Description: "הפעל את WSA Bluetooth Bridge אוטומטית עם Windows"; GroupDescription: "הפעלה אוטומטית:"; Flags: checkedonce

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "WSABluetoothBridge"; ValueData: """{app}\{#MyAppExeName}"" --background"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"; Description: "הפעל את WSA Bluetooth Bridge"; Flags: nowait postinstall skipifsilent
Filename: "{app}\Install-WsaSystem.ps1"; Parameters: "-ExecutionPolicy Bypass -NoProfile"; Description: "נסה להתקין את רכיב המערכת בתוך WSA"; Flags: postinstall shellexec skipifsilent unchecked

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM WsaBluetoothHost.exe /F"; Flags: runhidden; RunOnceId: "StopBridge"
