# Licensing

Anchorline is free software. This page says which licence covers what.

## The app: GNU GPL version 2

Anchorline is licensed under the GNU General Public License, version 2
only (`GPL-2.0-only`), with the additional permission for app stores
below. The full licence text is in [`LICENSE`](LICENSE).

Version 2 matches Subsurface, whose code is GPLv2-only and can therefore
be reused in Anchorline.

## Additional permission for app store distribution

As a special exception to the GNU General Public License version 2, the
copyright holders of Anchorline give you permission to distribute
Anchorline, or a work based on it, through an app store such as the Apple
App Store, the Mac App Store or Google Play. This holds even where that
store's terms of service, usage rules or technical measures (such as code
signing, digital rights management or limits on the number of devices)
place restrictions on recipients that section 6 of the GNU General Public
License version 2 would not otherwise allow.

This permission applies only if the complete corresponding source code of
the version you distribute is available to anyone, free of charge, under
the GNU General Public License version 2 together with this permission.

This permission covers only code whose copyright holders have granted it:
the Anchorline authors, and every contributor who accepted it under
[`CONTRIBUTING.md`](CONTRIBUTING.md). It does not cover third-party code
in this repository that is under its own licence, listed in
[`NOTICE.md`](NOTICE.md).

If you modify Anchorline, you may extend this permission to your version,
but you are not obliged to. If you do not wish to, delete this section
from your version.

## Third-party code and assets

Some files come from, or are based on, other projects and keep their own
licence. The main one is the Shearwater dive log parser, which is
translated from libdivecomputer and stays under the GNU Lesser General
Public License, version 2.1 or later
([`LICENSES/LGPL-2.1.txt`](LICENSES/LGPL-2.1.txt)). The full list, with
copyright holders, is in [`NOTICE.md`](NOTICE.md).

The SOLO bridge firmware in [`firmware/solo_bridge/`](firmware/solo_bridge/)
is a separate program that runs on the bridge hardware. It has its own
licence, Apache-2.0, in that folder.

## The name and logo

The licences in this repository cover the code, not the brand. The name
"Anchorline", the Anchorline logo and the app icons (in `assets/brand/`,
`assets/icon/`, the iOS and macOS `AppIcon` sets, the Android launcher
icons, `web/` and `windows/runner/resources/`) are not licensed for use
by others. They are included so the official app can be built from this
repository.

If you publish a modified version or a fork, give it a different name and
replace the logo and icons. You may still say, factually, that your
version is based on Anchorline.

## Contributing

Contributions are accepted under the GPL version 2, together with the app
store permission above, and need a Developer Certificate of Origin
sign-off. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
