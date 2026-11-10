# Contributing to Anchorline

This is a small project — the workflow below is the bare minimum that gives
us traceability ("why was this changed?") and keeps `main` always shippable.

## TL;DR

1. **Open an issue first** for every bug / feature / chore. The issue is
   where the discussion lives; the code is just the resolution.
2. **Branch from `main`** with a descriptive name:
   `fix/123-jwt-expired-stall`, `feat/45-surface-gf-port`,
   `chore/12-bump-flutter`. Number = issue number.
3. **Write tests** for the change (TDD where possible — see CLAUDE.md).
4. **Conventional Commits** for messages: `fix(sync): never hand …`,
   `feat(import): per-dive progress …`, `chore(version): 1.0.0+27 → +28`.
   **Sign off every commit** with `git commit -s` (see the licence
   section below).
5. **Open a PR** linked to the issue (`Closes #123`). Wait for green CI.
6. **Squash merge** so each issue lands as one clean commit on `main`.
7. **Delete the branch** after merge.

## Licence of your contribution

By contributing to Anchorline, you agree that your contribution is
licensed under the GNU General Public License, version 2
([`LICENSE`](LICENSE)). You also grant the additional permission for app
store distribution described in [`LICENSING.md`](LICENSING.md). That
permission lets the official app ship through the Apple App Store, the
Mac App Store and Google Play.

If your contribution includes code from another project, say so in the
pull request, keep that project's copyright and licence notices, and add
it to [`NOTICE.md`](NOTICE.md). Code from libdivecomputer (LGPL 2.1 or
later) and Subsurface (GPL version 2) is welcome on those terms.

The name "Anchorline" and its logo stay with the project; contributing
code doesn't change that. See [`LICENSING.md`](LICENSING.md).

### Sign your commits (Developer Certificate of Origin)

Every commit needs a `Signed-off-by` line. It certifies that you wrote the
change, or otherwise have the right to submit it under the licence above,
as set out in the Developer Certificate of Origin 1.1
(<https://developercertificate.org>). Add it with:

```
git commit -s
```

This adds a line like `Signed-off-by: Your Name <you@example.com>`. Use
your real name and an email address you can be reached at.

## Why this matters

The cost is ~2 minutes per change. The payoff:

- `git log` becomes a chronicle of *decisions*, not raw edits.
- Every commit on `main` ties to an issue with the *why*.
- `main` stays green so TestFlight / Play Internal cuts can happen any time.
- Bringing on a contributor doesn't require explaining the whole project to
  them — they can read the issues + commits.

## Workflow in detail

### 1. Issue first

Use the bug or feature template. Templates auto-suggest a title prefix
(`fix:` / `feat:`) and the right label.

Categories:

- **`bug`** — something is wrong. Include a repro.
- **`enhancement`** — a new feature or improvement.
- **`chore`** — infrastructure, deps, version bumps.
- **`question`** — *don't open these as issues*; use GitHub Discussions.

### 2. Branch

```
git checkout main
git pull
git checkout -b fix/123-short-description
```

Branch name format: `<type>/<issue-number>-<kebab-case-summary>`.

Types match the commit prefix: `fix/`, `feat/`, `chore/`, `docs/`,
`refactor/`, `test/`.

### 3. Code

- Follow the patterns in `CLAUDE.md`.
- Write a failing test first when fixing a bug — the test is what proves
  the fix, both now and against future regressions.
- Run `flutter analyze` and `flutter test` locally; both must pass before
  you push.
- Parser changes must keep every fixture in `test/fixtures/` passing.
- Write commit messages, code comments and documentation in English.

### 4. Commit

Conventional Commits style:

```
fix(sync): never hand PowerSync an expired JWT

`fetchCredentials` previously swallowed `refreshSession` failures and
returned the existing (often expired) session anyway, causing PowerSync
to hammer the server with PSYNC_S2103 …
```

The first line is what shows up in `git log --oneline`. Make it count.

Scope is the area of the code: `sync`, `ble`, `import`, `ui`, `subsurface`,
`analysis`, `deco`, `build`, etc.

### 5. Pull request

```
git push -u origin fix/123-short-description
gh pr create
```

The PR template prompts you for:
- A 1-3 bullet summary.
- The issue it closes (`Closes #123`).
- The test plan you actually ran.

### 6. Merge

- Squash merge (one commit on `main` per issue).
- Delete the branch (GitHub button or `git push origin :branch-name`).
- The issue auto-closes if you used `Closes #N` syntax.

### 7. Releases

Tag `main` when you cut a TestFlight / Play Internal build:

```
git tag -a v1.0.0+28 -m "v1.0.0+28: JWT fix, dive numbering, SurfGF, drain queue"
git push --tags
```

The build number in `pubspec.yaml` is the source of truth.

## Things to avoid

- **Pushing directly to `main`**. Even for a one-line fix — open a PR.
  Direct pushes break the "every change has an issue" invariant.
- **Long-lived feature branches**. If a branch lives more than a week,
  it's probably accumulated enough conflict + drift that rebasing hurts.
  Split into smaller PRs.
- **Mixing concerns in one PR**. "While I was in there I also fixed…" is
  how three-line PRs become three-day reviews. Open a separate issue.
- **Commit messages that describe the patch, not the change**. "Update
  foo.dart" is useless; "fix(sync): retry refresh on expired token" is
  what `git blame` should show three months later.

## CI

GitHub Actions runs on every PR (config in `.github/workflows/`). At
minimum, expect `flutter analyze` + `flutter test` to be green before a
PR can merge. Mac App Store / TestFlight builds remain manual — see
CLAUDE.md for the recipe.
