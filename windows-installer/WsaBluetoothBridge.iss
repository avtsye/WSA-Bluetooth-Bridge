; WSA Bluetooth Bridge installer
#define MyAppName "WSA Bluetooth Bridge"
#define MyAppVersion "0.8.2"
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
SetupIconFile=..\artifacts\windows-host-lite\app.ico
SetupLogging=yes

[Files]
Source: "..\artifacts\windows-host-lite\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\artifacts\wsa-system-module.zip"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\artifacts\android-client\app-debug.apk"; DestDir: "{app}"; DestName: "WsaBluetoothBridgeClient.apk"; Flags: ignoreversion
Source: "Install-WsaSystem.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Upgrade-Wsa.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\WSA Bluetooth Bridge"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\WSA Bluetooth Bridge"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "צור קיצור דרך בשולחן העבודה"; GroupDescription: "קיצורי דרך:"
Name: "autostart"; Description: "הפעל את WSA Bluetooth Bridge אוטומטית עם Windows"; GroupDescription: "הפעלה אוטומטית:"; Flags: checkedonce

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "WSABluetoothBridge"; ValueData: """{app}\{#MyAppExeName}"" --background"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\Upgrade-Wsa.ps1"" -ForceRoot"; StatusMsg: "מכין WSA עם Root/Magisk..."; Flags: waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\Install-WsaSystem.ps1"""; StatusMsg: "מתקין את רכיב Android/Audio HAL..."; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"; Flags: nowait runhidden

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM WsaBluetoothHost.exe /F"; Flags: runhidden; RunOnceId: "StopBridge"
