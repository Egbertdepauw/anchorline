; Anchorline Windows installer — Inno Setup 6 script.
;
; To produce an .msi-like installer .exe:
;   1. Build the Flutter Windows release: `flutter build windows --release`
;      (must run ON a Windows machine — Flutter doesn't cross-compile
;      Windows binaries from macOS or Linux). For the nightly, set the
;      environment variable ANCHORLINE_CHANNEL=nightly for that build (see
;      windows/CMakeLists.txt) and pass /DChannel=nightly to ISCC below.
;   2. Install Inno Setup 6 (https://jrsoftware.org/isdl.php).
;   3. From the repo root, run:
;        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ^
;          /DMyAppVersion=<V> /DMyAppBuild=<N> /DChannel=<release|nightly> ^
;          windows\installer\anchorline.iss
;      ISCC reads ..\..\build\windows\x64\runner\Release\ and packages
;      everything into windows\installer\Output. The file is
;      Anchorline-<V>-windows-x64.exe for the release channel and
;      Anchorline-Nightly-<V>-<N>-windows-x64.exe for the nightly. Without the
;      flags you get a release 1.0.0 build 0, which is enough for a local run.
;
; Output is a standard NSIS-style installer .exe (Inno Setup doesn't
; produce true .msi files — for .msi you'd use WiX, which is a much
; bigger lift). The landing page on staging.despaankamer.nl serves
; this .exe under the name it is built with (despite the .msi naming
; convention the user originally asked for — Inno is the path of
; least resistance and the result behaves identically from a user's
; perspective).
;
; Code signing: for production we want to avoid Windows SmartScreen
; warnings. That requires an EV Code Signing Certificate (~€350-700/yr
; from Sectigo / DigiCert). Without it, testers see a "Windows
; protected your PC" prompt on first launch — they click "More info"
; → "Run anyway". Acceptable for beta, not for store release.

#define MyAppPublisher "De Spaankamer"
#define MyAppURL "https://staging.despaankamer.nl/anchorline"
#define MyAppExeName "Anchorline.exe"
; CI overrides these with ISCC's /DMyAppVersion=<V> /DMyAppBuild=<N>
; /DChannel=<release|nightly> flags. MyAppVersion is plain X.Y.Z (no +N
; build suffix); MyAppBuild is the build counter and becomes the fourth part
; of the file version. The defaults below are for local manual runs.
#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif
#ifndef MyAppBuild
#define MyAppBuild "0"
#endif
#ifndef Channel
#define Channel "release"
#endif
#if Channel != "release" && Channel != "nightly"
#error Channel must be release or nightly: pass /DChannel=release or /DChannel=nightly
#endif

; The nightly is a separate app that installs next to the release: its own
; name (and so install folder and Start-menu entry) and its own AppId (below).
#if Channel == "nightly"
#define MyAppName "Anchorline Nightly"
#else
#define MyAppName "Anchorline"
#endif

[Setup]
; AppId must NEVER change across versions — Windows uses it to recognise
; "this is an upgrade of the same app". Generated once via Inno Setup's
; Tools → Generate GUID; do not regenerate. The same goes for the nightly's
; own AppId: it is what keeps the nightly from upgrading the release.
#if Channel == "nightly"
AppId={{077F972D-571A-4826-A633-D89426861B47}
OutputBaseFilename=Anchorline-Nightly-{#MyAppVersion}-{#MyAppBuild}-windows-x64
#else
AppId={{8C5A1F90-2B4E-4A6A-9D3F-7B1C2E8A0F65}
OutputBaseFilename=Anchorline-{#MyAppVersion}-windows-x64
#endif
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
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
; Anchorline keeps its user data outside {app}:
;   %LOCALAPPDATA%\De Spaankamer\Anchorline  databases (ccrlogger.sqlite,
;       powersync.db), subsurface_clone\, the BLE debug log and the
;       attachments\ cache. Builds before #135 kept the first four in the
;       user's Documents folder; the app moves them here on first start.
;       The folder is decided in lib/data/app_data_folder.dart.
;   %APPDATA%\De Spaankamer\Anchorline  preferences and the encrypted
;       secure-storage file (its key lives in Windows Credential Manager).
; Uninstall removes the app binaries but PRESERVES user data — same
; convention as macOS / iOS. Testers who reinstall keep their imported
; dives. "{app}\data" below is Flutter's asset folder, not user data.
Type: filesandordirs; Name: "{app}\data"
