# Anchorline Linux distribution — x64 AppImage

Sibling to `docs/WINDOWS_DISTRIBUTION.md` and `docs/MACOS_DISTRIBUTION.md`.
Covers building the Linux x64 release and packaging it as an AppImage.
The recipe lives in `linux/packaging/`.

**Build host: Ubuntu 22.04 x64.** Building on the oldest LTS we support
keeps the glibc floor at 2.35, so the AppImage runs on 22.04 and newer
(and on other distributions with glibc ≥ 2.35; Subsurface sync is the
exception, §3). On any other machine,
including an Apple Silicon Mac, the build runs in a `linux/amd64` Docker
container. On a Mac, Docker Desktop runs it under Rosetta emulation:
slow, but it works.

## 1. Toolchain

| What | Where it comes from |
|---|---|
| Ubuntu 22.04 x64 | `linux/packaging/Dockerfile` (`ubuntu:22.04`, built with `--platform linux/amd64`), or an `ubuntu-22.04` runner. |
| Flutter **3.44.0** stable (`559ffa3f75`) | Pinned in the Dockerfile by version, revision and tarball sha256. Bump it in lockstep with `.github/workflows/check.yml`. |
| Build packages: clang, cmake, ninja, GTK 3, libsecret, libcurl, OpenJDK 21, ImageMagick, patchelf | `linux/packaging/install_build_deps.sh`; the comments there say which plugin needs what. |
| appimagetool **1.9.1** + type2 runtime **20251108** | Same script; fixed upstream releases, sha256-checked, installed in `/opt/appimagetool`. |

A JDK is needed at build time only: `sentry_flutter` → `package:jni` does
`find_package(JNI)` (§4).

The Docker route needs nothing but Docker (Docker Desktop on a Mac).
Directly on an Ubuntu 22.04 x64 machine or runner:

```bash
sudo linux/packaging/install_build_deps.sh
# plus Flutter 3.44.0 on PATH
```

## 2. Build the release

With Docker, from a checkout of this repo:

```bash
linux/packaging/build_in_docker.sh --version <x.y.z> --build <N> --date <yyyy-MM-dd>
```

This builds the committed tree of `HEAD` (pass `--ref <commit>` for
another commit; uncommitted changes are never included). The tree goes
into the container as a `git archive`, so the build doesn't touch the
checkout's `.dart_tool/` or `build/`. The Flutter SDK is cached in the
image, the pub cache in the Docker volume `anchorline-linux-pub-cache`.
The recipe itself (`linux/packaging/`) is used as it is on disk.

On an Apple Silicon Mac (Rosetta), the first run takes about 7 minutes:
about 4 to build the image, 3 for the app. Later runs reuse the image
and the pub cache and take about 2.5 minutes; every run compiles the app
from scratch.

Without Docker, on Ubuntu 22.04 x64 (what the CI job will run):

```bash
linux/packaging/build_appimage.sh --version <x.y.z> --build <N> --date <yyyy-MM-dd>
```

Both run `flutter build linux --release` with the five release defines,
written out as separate arguments:

```
--dart-define=BUILD_CHANNEL=release --dart-define=DISTRIBUTION_CHANNEL=website --dart-define=APP_VERSION=<x.y.z> --dart-define=APP_BUILD=<N> --dart-define=APP_BUILD_DATE=<yyyy-MM-dd>
```

No `dart_defines.json` is needed: `SENTRY_DSN` has the production DSN as
its compiled-in default (`lib/main.dart`). The script stops if the build
date is missing from `libapp.so`, or if `libapp.so` contains
`release --dart-define` (the defines were passed as one glued string).

Output: `build/desktop-<x.y.z>+<N>/Anchorline-<x.y.z>-linux-x64.AppImage`,
and its sha256 at the end of the log. The unpacked AppDir stays in
`build/linux-appimage/Anchorline.AppDir` (without Docker only).

Users run it with `chmod +x Anchorline-*.AppImage && ./Anchorline-*.AppImage`.
The runtime mounts the image with FUSE 3 (`fusermount3`), which Ubuntu
22.04 and newer install by default; `libfuse2` is not needed. Without
FUSE, `./Anchorline-*.AppImage --appimage-extract-and-run` works too.

## 3. What is in the AppImage

```
AppRun                               starts usr/bin/anchorline
nl.despaankamer.ccrlogger.desktop    Name=Anchorline, Exec=anchorline
nl.despaankamer.ccrlogger.png        512 px, from assets/brand/launcher-1024.png
.DirIcon -> nl.despaankamer.ccrlogger.png
usr/bin/                             the Flutter bundle (anchorline, lib/, data/)
usr/share/applications/, usr/share/icons/hicolor/512x512/apps/
```

The desktop id matches the GTK application id (`linux/CMakeLists.txt`),
so the window and an integrated launcher (AppImageLauncher, Gear Lever)
belong together.

User data stays outside the AppImage, so replacing the file with a newer
one keeps it: the databases, the Subsurface clone and the BLE log go to
`$XDG_DATA_HOME/nl.despaankamer.ccrlogger` (normally
`~/.local/share/nl.despaankamer.ccrlogger`; `lib/data/app_data_folder.dart`
decides), secrets to the desktop keyring through libsecret.

System libraries are not bundled. The AppImage expects what an Ubuntu
22.04 desktop install already has: GTK 3, libsecret (secure storage),
libcurl 4 (Sentry), OpenSSL 3, zlib and Mesa's EGL/GL. The exception is
libssh2, which desktops don't install: the script ships
`git2dart_binaries`' own copy as `lib/libssh2.so.1` and points
`libgit2.so`'s RUNPATH at `$ORIGIN` with patchelf.

**glibc floor.** Everything the build compiles needs glibc 2.34 at most,
so the app runs on Ubuntu 22.04 (2.35). The prebuilt `libgit2.so` from
`git2dart_binaries` 1.12.1 was built on Ubuntu 24.04 and needs glibc
2.38 (`__isoc23_strtol`, `__isoc23_strtoul`). The app only opens it for
Subsurface sync, so on glibc < 2.38 (Ubuntu 22.04, Debian 12) the app
starts and works, but Subsurface sync can't load libgit2. Ubuntu 24.04,
Debian 13 and Fedora 39 or newer are fine. Fixing this needs a libgit2
built on an older glibc, upstream or here.

## 4. Known quirks (handled in the recipe)

| Symptom | Cause | Status |
|---|---|---|
| `libdartjni.so` → `libjvm.so => not found` on a user's machine | `package:jni` links the build machine's `libjvm.so`. It is only used by `sentry_flutter` on Android; on Linux Sentry runs through sentry-native and nothing opens `libdartjni.so` | `build_appimage.sh` leaves `libdartjni.so` out of the AppDir. |
| `Could NOT find JNI (missing: JAVA_AWT_LIBRARY JAVA_JVM_LIBRARY …)` | `package:jni` needs a JDK at build time; CMake 3.22's FindJNI doesn't find Ubuntu's OpenJDK 21 without `JAVA_HOME`, and also wants `libjawt.so`, which the `-headless` JDK lacks | `install_build_deps.sh` installs the full `openjdk-21-jdk`; `build_appimage.sh` sets `JAVA_HOME` to it unless one is set already (setup-java on a runner). |
| `libssh2.so.1 => not found` for `libgit2.so` | `git2dart_binaries` links libssh2 but only bundles `libgit2.so` | Shipped as `lib/libssh2.so.1`, with `libgit2.so`'s RUNPATH set to `$ORIGIN` (§3). |
| `ldd lib/lib*_plugin.so` says `libflutter_linux_gtk.so => not found` | Flutter installs plugin libraries with their build-tree RUNPATH (`…/linux/flutter/ephemeral` on the build machine). Harmless at runtime (the executable has loaded `libflutter_linux_gtk.so` by then), but it leaks a build path | The script sets their RUNPATH to `$ORIGIN`. It also drops `crashpad_handler`'s RUNPATH, which is all empty entries (= the current directory). |
| `fuse: device not found` / `dlopen(): error loading libfuse.so.2` | No FUSE in containers and CI runners | appimagetool is unpacked once at install time; to start an AppImage there, use `--appimage-extract-and-run` or `APPIMAGE_EXTRACT_AND_RUN=1`. |
| `cannot execute binary file: Exec format error` when running any AppImage in Docker on an Apple Silicon Mac | AppImages carry a magic (`AI\x02`) in ELF header bytes 8–10, which the emulator's binfmt rule (Rosetta, QEMU) rejects. Real x64 kernels don't care | `install_build_deps.sh` clears those bytes in its copy of appimagetool before unpacking it. To test-run the built AppImage in such a container, do the same to a copy (`printf '\x00\x00\x00' \| dd of=copy.AppImage bs=1 seek=8 count=3 conv=notrunc`). Never ship a patched file. |
| appimagetool downloads a runtime | By default it fetches the newest "continuous" runtime | The pinned runtime is passed with `--runtime-file`. |
| Configure fails with `ANCHORLINE_CHANNEL must be unset, release or nightly` | `linux/CMakeLists.txt` refuses unknown channels | The script builds the release only and sets `ANCHORLINE_CHANNEL=release` itself. |

## 5. Not covered yet

- **Nightlies.** A nightly AppImage needs `ANCHORLINE_CHANNEL=nightly`,
  `--dart-define=BUILD_CHANNEL=nightly`, the `nl.despaankamer.ccrlogger.nightly`
  desktop id and the `Anchorline-Nightly-<x.y.z>-<n>-linux-x64.AppImage`
  name. The script refuses anything but the release until that is wired
  up (cloud-builds spec, §6).
- **Signing, update information, AppStream metainfo.** None yet;
  appimagetool runs with `--no-appstream`.
- **Hardware paths.** BLE import (BlueZ over D-Bus), Subsurface sync
  (libgit2) and the gas analyzer's serial port have not been tried from
  the AppImage on a real machine (cloud-builds spec, §12).

## 6. Versioning

Same numbers as the other platforms of the release: `--version` is the
`pubspec.yaml` build name, `--build` the build number, `--date` the
build date shown in Settings → About.
