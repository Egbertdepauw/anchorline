# Anchorline

A Swiss army knife for technical divers, especially rebreather divers.

## Getting Started

Anchorline is build by and for technical (rebreather) divers.
Shearwater dive computers are supported first-class. Other brands' Bluetooth
dive computers work through libdivecomputer and are marked "Not yet tested by
us" until we have a real recording from them (see below).

## Main functions
- Logging dives with O2 and pressure sensor data if available.
- Logging O2 cell life 
- Attaching images, videos and documents to logged dives
- Logging dive locations, buddies, tags, etc.
- Statistics, buddies, dive sites, deepest dive, longest, etc.
- Gas blending
- Gas Analysing (currently only with a Divesoft SOLO analyser)
- Gas analysis label printing via Phomemo M110 label printer
- Dive decompression and bailout gas planning

## Help us test your dive computer

Besides Shearwater, Anchorline can talk to many other brands' Bluetooth dive
computers through [libdivecomputer](https://www.libdivecomputer.org), but we
have only tested Shearwater with real hardware. Every other computer shows
"Not yet tested by us" on the import screen.

If you own one, switch on "Record this download" on the import screen, run the
import, then tap "Share this download". The file is a recording of your dive
computer's download. It contains the dives on the computer, its serial number
and any GPS positions it logged. Send it to recordings@anchorline.eu or attach
it to an issue at github.com/Egbertdepauw/anchorline/issues so we can check
your computer.

## Future ideas
- Sharing gas analysis between users
- Tagging users in dives
- Sharing to social media (Strava, Instagram, Facebook, X)
- registering C cards.

## Licence

Anchorline is free software under the GNU General Public License,
version 2 ([`LICENSE`](LICENSE)), with an additional permission that
allows distribution through app stores. The Shearwater parser is
translated from [libdivecomputer](https://www.libdivecomputer.org) and
keeps its LGPL 2.1 licence. See [`LICENSING.md`](LICENSING.md) for the
details and [`NOTICE.md`](NOTICE.md) for all third-party code and assets.

The name "Anchorline" and its logo are not covered by the licence; a fork
needs its own name.

Contributions are welcome; see [`CONTRIBUTING.md`](CONTRIBUTING.md).
