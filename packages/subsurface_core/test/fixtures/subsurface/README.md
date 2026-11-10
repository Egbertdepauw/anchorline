# Subsurface git-format fixtures

These files are real copies from the maintainer's personal Subsurface git
repository (kept locally, never pushed), with one change: the names of other
people (dive buddies, in `buddy` lines and in free-text notes) were replaced
with made-up names. Everything else is unmodified. They live here so the
parser/serializer can be tested against actual Subsurface output rather than a
synthetic approximation.

The set is deliberately small (one top-level file, three sites, five dives)
and chosen to exercise the format variations the parser cares about:

| Fixture                                     | What it exercises                                        |
| ------------------------------------------- | -------------------------------------------------------- |
| `00-Subsurface`                             | top-level `version` / `divecomputerid` / `fingerprint` / `units` / `prefs` |
| `sites/Site-0a9f7232`                       | minimal site (just name + GPS + geo)                     |
| `sites/Site-0acb7fe3`                       | another simple Dutch site (smoke test)                   |
| `sites/Site-ecaf8184`                       | multi-line `notes` with embedded `\"`-escaped quotes     |
| `dives/2026/04/04-Sat-13=30=15/`            | modern Petrel CCR with multi-sensor samples + many keyvalues |
| `dives/2025/05/04-Sun-09=48=36/`            | Petrel CCR using `o2pressure=` and non-indexed `bar` form |
| `dives/2026/04/27-Mon-11=33=43/`            | multi-line `notes` and minimal cylinder set              |
| `dives/2004/06/19-Sat-09=00=00/`            | very old manual dive — no `model` line, `lastmanualtime`, sparse samples, `weightsystem` |
| `dives/2020/08/18-Tue-16=00=27/`            | manually-added dive with airtemp / visibility / current / surge / chill / watersalinity |

If you regenerate these from the source repo (`/Users/egbert/Dev/CCRLog/ss_git`),
preserve byte-for-byte: the round-trip tests compare the serializer output
directly to the file on disk, so any normalisation breaks them.
