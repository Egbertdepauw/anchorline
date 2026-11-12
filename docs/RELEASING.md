# Releasing Anchorline

Status: agreed 2026-11-12. The schedule starts when the app goes public
on the App Store and Google Play. Until then, releases happen whenever
they are ready, the way they do now.

Anchorline is a side project. The schedule is meant to be something one
person can keep up in evenings and on weekends. It is not a promise to
ship every two weeks.

## The two-week train

```
 Week 1                         Week 2
 Sun ─────────────────────────── Tue   Wed ─── Fri   Sat      Sun
 ◄────────── MERGE WINDOW ──────────►  ◄─ FREEZE ─►  BUILD    RELEASE
  features, refactors and               fixes only    bump,    submit to the stores,
  dependency bumps land on main         for what's    all      put the desktop builds
                                        already in    builds   on the website
```

| Day | Phase | What happens |
|---|---|---|
| Sun (release day) to Tue of week 2 | **Merge window** | Any PR with green CI that has been read and accepted can merge. Merge large or risky PRs early in the window, so they get the most use before the build. |
| Wed to Fri of week 2 | **Freeze** | Only fixes for things already merged in this window. Other PRs stay open and wait for the next window. Deploy any server changes the release needs (see below). |
| Sat of week 2 | **Build** | Bump the version, build every platform, and test on a real dive computer at least once: import a dive and open its profile. |
| Sun of week 2 | **Release** | Submit to the App Store and Google Play, and publish the macOS, Windows and Linux builds on the website. This Sunday also opens the next merge window. |

Store review takes a day or two, so it runs during the week.

### Rules

- **No cargo, no train.** If nothing user-facing merged during the
  window, skip the release. The next window opens on schedule anyway.
- **Hotfixes are for P0 only.** Examples: data loss, a crash on start,
  broken import or broken sync. A hotfix goes out outside the schedule as
  a patch release. Anything less waits for the next train.
- **Server changes ship before the app that needs them.** Supabase
  migrations, PowerSync sync rules and Worker changes are deployed during
  the freeze, before the build. They must keep working with the builds
  that are already out there, because people do not update straight away.
- **A slipped date is fine.** If the build or the test fails, or life gets
  in the way, the release moves to the next evening or the next weekend.
  The merge window stays closed until it ships.
- **One milestone per release.** Each release gets a GitHub milestone
  (for example `1.2.0`). PRs merged in the window get that milestone,
  and its list of PR titles is the starting point for the release notes.

## Version numbers

`pubspec.yaml` holds `version: <major>.<minor>.<patch>+<build>`.

- Each train bumps the **minor** version: 1.2.0, 1.3.0, and so on.
- A hotfix bumps the **patch**: 1.2.1.
- The **build** number goes up by one for every build uploaded to a
  store, whether it is a train release, a hotfix or a beta. The stores
  refuse a build number they have already seen.

## Related documents

- `docs/BETA_DISTRIBUTION.md`: build commands per platform and the
  dart-defines every release build needs.
- `docs/APP_STORE_SUBMISSION.md`: App Store and Google Play submission.
- `docs/MACOS_DISTRIBUTION.md`, `docs/WINDOWS_DISTRIBUTION.md`,
  `docs/LINUX_DISTRIBUTION.md`: desktop packaging and signing.
- `docs/RELEASE_AND_MONETISATION.md`: what is free and what is paid, and
  where each platform is distributed.
