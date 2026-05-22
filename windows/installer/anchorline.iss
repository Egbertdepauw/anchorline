; Anchorline Windows installer — Inno Setup 6 script.
;
; To produce an .msi-like installer .exe:
;   1. Build the Flutter Windows release: `flutter build windows --release`
;      (must run ON a Windows machine — Flutter doesn't cross-compile
;      Windows binaries from macOS or Linux).
;   2. Install Inno Setup 6 (https://jrsoftware.org/isdl.php).
;   3. From the repo root, run:
;        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows\installer\anchorline.iss
;      ISCC reads ..\..\build\windows\x64\runner\Release\ and packages
;      everything into windows\installer\Output\Anchorline-Setup-x.y.z.exe.
;
; Output is a standard NSIS-style installer .exe (Inno Setup doesn't
; produce true .msi files — for .msi you'd use WiX, which is a much
; bigger lift). The landing page on staging.despaankamer.nl serves
; this .exe as Anchorline-Setup-<version>.exe (despite the .msi naming
; convention the user originally asked for — Inno is the path of
; least resistance and the result behaves identically from a user's
; perspective).
;
; Code signing: for production we want to avoid Windows SmartScreen
; warnings. That requires an EV Code Signing Certificate (~€350-700/yr
; from Sectigo / DigiCert). Without it, testers see a "Windows
; protected your PC" prompt on first launch — they click "More info"
; → "Run anyway". Acceptable for beta, not for store release.

#define MyAppName "Anchorline"
#define MyAppPublisher "De Spaankamer"
#define MyAppURL "https://staging.despaankamer.nl/anchorline"
#define MyAppExeName "Anchorline.exe"
; Version is overridden by ISCC's /DMyAppVersion=1.0.0+5 flag from CI.
; Default below is for local manual runs.
#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif

[Setup]
; AppId must NEVER change across versions — Windows uses it to recognise
; "this is an upgrade of the same app". Generated once via Inno Setup's
; Tools → Generate GUID; do not regenerate.
AppId={{8C5A1F90-2B4E-4A6A-9D3F-7B1C2E8A0F65}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputBaseFilename=Anchorline-Setup-{#MyAppVersion}
OutputDir=Output
Compression=lzma2/ultra
SolidCompression=yes
; Modern UI looks closer to a 2026 app installer than the default
; "Classic" wizard.
WizardStyle=modern
; 64-bit only — the Flutter Windows runner is x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; No admin needed when installing per-user under {localappdata}\Programs;
; with the default {autopf} install path (Program Files), we DO need
; admin elevation. Keep that — beta testers expect that flow.
PrivilegesRequired=admin
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The Flutter Windows release output ships the .exe plus runtime DLLs,
; data/, and the entire flutter_assets tree. Pull the whole directory.
Source: "..\..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; \
    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Anchorline keeps its local database + secrets under %LOCALAPPDATA%.
; Uninstall removes the app binaries but PRESERVES user data — same
; convention as macOS / iOS. Testers who reinstall keep their imported
; dives.
Type: filesandordirs; Name: "{app}\data"
