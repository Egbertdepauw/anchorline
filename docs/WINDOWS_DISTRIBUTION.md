# Anchorline Windows distribution — x64 build + installer

Sibling to `docs/MACOS_DISTRIBUTION.md` and `docs/APP_STORE_SUBMISSION.md`.
Covers building the Windows x64 release and packaging the Inno Setup
installer. Written after the first successful bring-up (issue #74) so the
next machine doesn't rediscover the prerequisites the hard way.

**Host requirement: native x64 Windows.** Flutter cannot cross-compile
Windows from macOS/Linux, and a Windows-on-ARM VM with x64 emulation
trips sentry-native's crashpad ARM assembly (issue #3). A plain x64
Windows 10/11 VM or machine is the supported path.

## 1. Toolchain (one-time setup)

Install in this order:

| # | What | Notes |
|---|---|---|
| 1 | **Visual Studio 2022 Community** | Tick the **"Desktop development with C++"** workload (MSVC v143+, a Windows 10/11 SDK, C++ CMake tools). Newer VS lines bundle CMake ≥ 4.0 — fine: the repo carries the pdfium policy fixup (see §4). |
| 2 | **Git for Windows** | https://git-scm.com/download/win |
| 3 | **Flutter SDK (stable, x64)** | Match the version the repo is developed against (`flutter --version` on the Mac; 3.44.0 at time of writing). Extract to a short path like `C:\src\flutter` (not Program Files), add `C:\src\flutter\bin` to PATH. |
| 4 | **Temurin JDK (LTS, x64)** | https://adoptium.net — required because `sentry_flutter` → `package:jni`'s Windows CMake does `find_package(JNI)`. In the installer, enable **"Set JAVA_HOME variable"**. Must be a JDK (has `include\jni.h`), not a JRE. |
| 5 | **Inno Setup 6** | https://jrsoftware.org/isdl.php — compiles `windows/installer/anchorline.iss`. Inno Setup 7 (7.0.x, July 2026+) also compiles the script and can be installed side-by-side; adjust the ISCC path accordingly. |
| 6 | **Developer Mode ON** | Settings → Privacy & security → For developers. Flutter's plugin symlinks need it. |

Recommended: add a Windows Defender exclusion for `C:\src\` — big native
builds are dramatically slower (and occasionally quarantined) without it.

## 2. Project setup

```powershell
git clone https://github.com/Egbertdepauw/ccrlogger.git C:\src\ccrlogger
cd C:\src\ccrlogger

# dart_defines.json is gitignored (carries SENTRY_DSN). Copy it from
# another dev machine, or recreate from the committed template:
copy dart_defines.example.json dart_defines.json   # then paste the real DSN in

flutter doctor     # Visual Studio + Windows toolchain must be green
flutter pub get
```

The build *succeeds* without `dart_defines.json` — Sentry just stays
disabled. Include it for any build you intend to distribute.

## 3. Build the release

```powershell
flutter build windows --release `
  --build-number=<N> --build-name=<x.y.z> `
  --dart-define-from-file=dart_defines.json
```

Output: `build\windows\x64\runner\Release\` — `Anchorline.exe` plus
runtime DLLs and the `data\` tree. **The whole folder is the app**; the
bare .exe does not run without its siblings. Sanity checks:

- `libgit2.dll`, `libssh2.dll`, `libcrypto-3-x64.dll`, `libssl-3-x64.dll`
  present next to the .exe (Subsurface Cloud sync's chain — bundled by
  `git2dart_binaries` ≥ 1.12.1).
- Launch the .exe once and open Settings → Subsurface sync to confirm
  libgit2 loads.

## 4. Known build-time quirks (already handled in-repo)

| Symptom | Cause | Status |
|---|---|---|
| `Compatibility with CMake < 3.5 has been removed` … `CMake step for pdfium failed` | pdfx configures pdfium in a nested build tree; CMake ≥ 4.0 rejects its ancient `cmake_minimum_required` | **Fixed in-repo**: `windows/CMakeLists.txt` seeds `ENV{CMAKE_POLICY_VERSION_MINIMUM}=3.5`. A CMake deprecation *warning* still prints — harmless. |
| `Could NOT find JNI (missing: JAVA_INCLUDE_PATH …)` | `sentry_flutter` → `package:jni` needs a JDK at build time | **Toolchain prereq**: install the JDK + `JAVA_HOME` (§1.4), open a fresh terminal. |
| `error MSB3073 … cmake_install.cmake` at the very end of the build | `git2dart_binaries` ≤ 1.10.4 referenced Windows DLLs it never shipped, so the INSTALL copy died | **Fixed by the `^1.12.1` pin.** If it ever reappears after a binaries bump, audit shipped files vs. the manifest in the pub archive (see CLAUDE.md "Known third-party defects"). |
| `error MSB8076: Only ARM, ARM64 and ARM64EC platforms are supported` (crashpad) | Building on Windows-on-**ARM** with the x64 toolchain | Not applicable on native x64. Tracked as issue #3. |

## 5. Package the installer

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" `
  /DMyAppVersion=<x.y.z> windows\installer\anchorline.iss
```

Output: `windows\installer\Output\Anchorline-Setup-<x.y.z>.exe` — a
per-machine (admin-elevated) installer that bundles the entire
`Release\` folder, creates Start-menu/desktop entries, and preserves
user data (`%LOCALAPPDATA%` database) on uninstall. Details and the
AppId contract live as comments in `anchorline.iss`.

(Inno Setup 7: same command with `Inno Setup 7\ISCC.exe`.)

## 6. Code signing / SmartScreen

The installer and .exe are currently **unsigned**. First-launch shows
"Windows protected your PC" → *More info* → *Run anyway*. Acceptable for
beta testers; for public distribution buy an OV/EV code-signing
certificate (~€350–700/yr, Sectigo/DigiCert), sign `Anchorline.exe` and
the setup .exe with `signtool`, and SmartScreen reputation builds from
there. Until then, mention the SmartScreen click-through in the download
page copy.

## 7. Versioning

Follow the shared `pubspec.yaml` version. Windows takes the build name
into the product/file version and the number as a suffix; stamp both on
the CLI as in §3 (same numbers as the iOS/macOS/Android artifacts of the
release). For direct-download installers the number is informational,
but keeping it in lockstep with the store builds makes support ("which
build are you on?") unambiguous.
