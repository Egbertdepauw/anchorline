# Subsurface copies of the Petrel 3 trace dives

These are real copies from the maintainer's personal Subsurface git
repository (kept locally, never pushed) of the eight dives that
`test/fixtures/raw/subsurface2.combined.txt` downloads from a Petrel 3
(serial `B89641E4`). `test/data/import/subsurface_copy_refresh_test.dart`
bootstraps them as Subsurface Cloud copies, replays the download on top, and
checks that every copy is refreshed under its own id.

The layout is relative to the dive-log root, like the fixtures in
`packages/subsurface_core/test/fixtures/subsurface/`: `dives/` holds the
`<year>/<month>/<day>-<weekday>-<hh>=<mm>=<ss>` folders, `sites/` the
`Site-<id>` files (the importer reads them from `01-Divesites/`, the test
copies them there).

| Folder                              | Start (UTC)         | Subsurface # | Trace dive # |
| ----------------------------------- | ------------------- | ------------ | ------------ |
| `dives/2026/03/19-Thu-12=04=31`     | 2026-03-19 12:04:31 | 701          | 718          |
| `dives/2026/03/20-Fri-11=28=48`     | 2026-03-20 11:28:48 | 702          | 717          |
| `dives/2026/03/21-Sat-12=33=52`     | 2026-03-21 12:33:52 | 703          | 716          |
| `dives/2026/03/29-Sun-08=54=46`     | 2026-03-29 08:54:46 | 704          | 715          |
| `dives/2026/04/04-Sat-13=30=15`     | 2026-04-04 13:30:15 | 705          | 714          |
| `dives/2026/04/05-Sun-09=38=49`     | 2026-04-05 09:38:49 | 706          | 713          |
| `dives/2026/04/12-Sun-11=10=28`     | 2026-04-12 11:10:28 | 707          | 712          |
| `dives/2026/04/19-Sun-09=41=42`     | 2026-04-19 09:41:42 | 708          | 711          |

Every start time equals the trace's to the second. The top-level
`00-Subsurface` is byte-identical to the one in the package fixtures, and the
five site files are the ones these dives reference.

## What was changed

Only the names of other people were replaced with made-up names: the
`buddy` lines, free-text `notes`, and a tag that contained a buddy's name
(it was renamed to `MOD2ANNA`). Nothing else differs from the source files.
Dive site names and GPS coordinates are kept as they are.

The round-trip and importer tests compare against the files byte for byte, so
preserve this if you regenerate them.
