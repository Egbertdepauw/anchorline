# Anchorline website — design (refresh)

Date: 2026-11-08
Status: approved in conversation on 2026-11-08; awaiting spec review
Supersedes: `2026-10-07-website-design.md`. That document stays for its
history and because PR #140 amends its §2; the contract it describes is
carried forward here unchanged in substance.
Context: `docs/RELEASE_AND_MONETISATION.md`,
`docs/superpowers/specs/2026-11-02-cloud-builds-design.md` (§8),
`docs/superpowers/specs/2026-10-07-subscriptions-entitlements-design.md`,
PR #140 (`tool/publish/`).

The website is its own project in its own repository. This spec lives in
the Anchorline app repository because two of its parts are built here:
the publish command and the format of the releases list the site reads.
The site repository gets a README that points back here.

## Why a refresh

The October design still holds. Since then: the cloud-builds spec and
PR #140 settled who writes the downloads bucket and how; the app got its
brand marks and selectable themes; a temporary landing page went up on
De Spaankamer's staging site; the stores turned out to need an
account-deletion address; and the legal texts still said "CCRLog". This
version folds all of that in, records the decisions taken on
2026-11-08, and is the document the site is built from.

## Goal

A public website for Anchorline that shows the app, says what it does
today and where it is going, offers the Windows and Linux downloads and
the store links, and hosts the legal pages the stores require, with new
builds and texts published from the Anchorline repository.

Success means:

- A visitor on a phone sees what Anchorline is, sees the app, and can
  get it for their platform without scrolling past the first screen.
- A new user finds a plain explanation of every screen of the app on
  the site, with a picture of that screen.
- Publishing a new build or a changed legal text needs no change to the
  site's repository and no site deploy.
- The privacy policy, the terms and the account-deletion page are always
  reachable, even when the bucket is down.
- The site cannot affect De Spaankamer's site, with which it shares a
  server.

## Decisions

"Egbert" marks decisions taken in conversation; "my call" marks choices
made while writing this up, for him to check.

| Question | Decision | By |
|---|---|---|
| Who publishes Anchorline | Egbert De Pauw personally. No company. The Apple team and every signing certificate already carry his name, so nothing is re-issued. | Egbert |
| Domain | `anchorline.eu`, registered 2026-11-08 at Nederhost, DNS moving to a Cloudflare zone (free plan). `anchorlineapp.com` as an optional redirect, not registered as of writing. | Egbert |
| Trademark | Checked in TMview on 2026-11-08. No EU trade mark. One live German class 9 mark, "ANCHORLINE ALWAYS ON THE LINE" (DPMA 302019215492, fall-protection and rescue equipment). Judged no blocker; to be mentioned to the lawyer who reads the terms. | Egbert, on my reading |
| Support address | `support@anchorline.eu`, received through Cloudflare Email Routing and forwarded to Egbert's mailbox. Replaces the Gmail address in every public text and store listing. | Egbert |
| Temporary address | `anchorline.despaankamer.nl`. Its DNS A record was added at Wix on 2026-11-08. The Caddy block that serves it is a change to SpaankamerWeb and needs Egbert's explicit OK as a separate step. | Egbert |
| Site repository | `/Users/egbert/Dev/nextjs/anchorline-web`, GitHub `Egbertdepauw/anchorline-web`. Private until the app repository goes public, then public with it. | Egbert |
| Interim landing page (`staging.despaankamer.nl/anchorline`) | Becomes a permanent redirect to the new site as soon as that answers on the temporary address; retargeted to `anchorline.eu` at go-live; its files deleted from SpaankamerWeb afterwards. Each step is a small SpaankamerWeb PR for Egbert's OK. | Egbert |
| Where the download files come from while the cloud-builds work is parked | The site is built and tested against a local fixture carrying the real 1.1.0 (build 44) files' names, sizes and checksums. The bucket is created later; releases are published by hand until the pipeline exists. The site switches from fixture to bucket by one setting. | Egbert |
| Home page shape | "App first": pitch, three real screenshots and the download row above the fold; then a tour of what it does today, a roadmap, free versus paid, supported computers, footer. Option A of the three mockups shown on 2026-11-08; the approved wireframe is committed next to this spec as `2026-11-08-website-design/home-wireframe-a.html`. | Egbert |
| Live dive profile | Kept, as the centrepiece of the "what it does today" tour rather than the hero. | My call, accepted |
| Look | The Anchorline brand only: hull black, reel orange, surface white, slack-water steel; Inter and JetBrains Mono. Dark only. The app's other themes are an app feature, not a site feature. | My call, accepted |
| Account deletion | A page on the site at `/delete-account`, linked from the footer and from the privacy policy, describing in-app deletion and an email route for people without the app. Its text is `docs/ACCOUNT_DELETION.md`, written by the in-app account-deletion work (its spec: `2026-11-08-account-deletion-design.md`) and published like the other legal texts. It replaces the page on GitHub Pages (`egbertdepauw.github.io/ccrlogger-legal/delete-account/`). | Egbert |
| Legal texts | `docs/PRIVACY.md` renamed and revised for Anchorline, with the "Deleting your account" section the deletion spec asks for; `docs/TERMS.md` drafted for a legal read; `docs/ACCOUNT_DELETION.md` from the deletion work. All three are published to the bucket by a new `content` action of the publish command (not in PR #140), run by a small workflow in the app repository when any of them changes on main. Until the bucket exists, the site serves the copies committed in its own repository. | Egbert |
| Languages | English only, built so more can be added. | Unchanged |
| Phone visitors before the stores are live | The beta links are public: a TestFlight public link and a Google Play testing link are site settings, shown as "Join the beta" where a store badge would be. With neither set, a "Coming to the App Store / Google Play" line. | Egbert |
| Screenshots | Shown inside a generic phone frame (the "emulator look"). Taken from Egbert's own logbook, with his permission given 2026-11-08, in the Wreck theme at phone size; user and buddy names anonymised and the account email never shown. The capture method is the builder's. | Egbert |
| Live profile data | One of Egbert's real dives and his own cells' mV history, with date, place, notes, serial numbers and any user or buddy names removed. The builder picks a representative dive; Egbert may veto. | Egbert |
| User manual | The site carries a simple manual: one page per screen of the app, each with a framed screenshot and a plain explanation of what the screen shows and what it is for (§4.6). Asked for on 2026-11-08. The texts live in the app repository under `docs/user/` and travel the same publishing route as the legal texts, so a change to a screen and to its page land in one PR. The page list and the page shape are my call, for Egbert to strike or add to. | Egbert; shape my call |
| Caddy reload | SpaankamerWeb's deploy copies the Caddyfile but does not reload Caddy, so each Caddy-block PR also adds a one-line `caddy reload` step to that deploy. The one-off server commands (creating `/opt/anchorline`, the first compose start) are Egbert's, from a checklist the builder writes; the builder verifies through the public address and gets no SSH access to the shared box. | Egbert, on my recommendation |

## Out of scope for the first version

- Account sign-in and subscription management on the site. Wanted
  later; the structure leaves room for it.
- Documentation beyond the manual (§4.6): tutorials, a searchable
  knowledge base, a PDF of the manual, translations, and an in-app help
  button that opens the matching manual page (companion work, later).
- Newsletter, blog, analytics, cookies beyond what the browser needs to
  show a page.
- The nightly downloads list. The contract allows for it (§2); the
  download page shows releases only until nightlies are produced.
- Linux distribution packages and a macOS Homebrew build (see "Later
  stages").
- Any change to SpaankamerWeb beyond the Caddy blocks, the Caddy reload
  step in its deploy, and the redirect named above.

## Design

### 1. Structure and stack

**Pages**

| Page | Path | Content | Source |
|---|---|---|---|
| Home | `/` | §4.1 | Site repository |
| Download | `/download` | Store links; current Windows and Linux installers with version, date, release notes, size and checksum; system requirements | Published content (§2) and site settings |
| Privacy policy | `/privacy` | | Published content, with a committed fallback |
| Terms | `/terms` | Including the subscription terms | Published content, with a committed fallback |
| Delete your account | `/delete-account` | §4.4 | Published content (`docs/ACCOUNT_DELETION.md`), with a committed fallback |
| Support | `/support` | The support address, where to report a problem, which information to include | Site repository |
| Manual | `/manual` | §4.6: the contents page | Published content (`docs/user/index.md`), with a committed fallback |
| Manual page | `/manual/<slug>` | §4.6: one screen of the app per page | Published content (`docs/user/<slug>.md` and its screenshots), with a committed fallback |

**Navigation.** The header carries the wordmark and three links: Manual,
Download, Support. Everything else is reached from the footer (§4.1,
item 6).

**Stack.** Next.js 16 with React 19 and Tailwind 4, the same generation
as De Spaankamer's site, so nothing new to learn; TypeScript strict;
Vitest for unit tests and Playwright for the browser test. No database,
no content-management system, no login, no cookies set by the site. One
container with no state of its own; it can be rebuilt or moved without
losing anything.

**Hosting.** A Docker image built by a GitHub Actions workflow in the
site repository, pushed to GitHub's container registry, run with Docker
Compose on the Hetzner server under `/opt/anchorline`, separate from
SpaankamerWeb's `/opt/spaankamer`. Details, all my calls:

- The container publishes no host port. It joins the Docker network
  SpaankamerWeb's Caddy already uses (compose project `spaankamer`,
  network `external`, declared as an external network in the Anchorline
  compose file), and Caddy proxies to it by container name.
- The Anchorline compose project is named `anchorline`. SpaankamerWeb's
  deploy runs `docker compose up --remove-orphans` for its own project
  only, so it never touches this container.
- Memory limit 512 MB and `restart: unless-stopped`.
- The deploy workflow mirrors SpaankamerWeb's: build and push on every
  push to `main`, then over SSH pull the image and
  `docker compose up -d --force-recreate`. It uses its own deploy key
  and the same host secrets, set by Egbert in the site repository's
  settings.
- Caddy is SpaankamerWeb's. The two blocks it needs, one for the
  temporary address now and one for `anchorline.eu` plus a `www`
  redirect at go-live, are the only SpaankamerWeb changes, each in its
  own PR for Egbert's OK.

**Settings.** The site reads a handful of environment variables, with
defaults for development:

| Setting | Meaning |
|---|---|
| `SITE_URL` | The public address, for canonical links and the sitemap |
| `DOWNLOADS_BASE_URL` | Where `releases/manifest.json` and `content/` live. Default: the site's own `/fixtures/` route, which serves the committed fixture (§2). |
| `APP_STORE_URL`, `MAC_APP_STORE_URL`, `PLAY_STORE_URL` | Store listings; empty hides the badge |
| `TESTFLIGHT_URL`, `PLAY_TESTING_URL` | Public beta links. Shown as "Join the beta" for iOS and macOS (TestFlight covers both) and for Android when the matching store URL is empty. When both the store and the beta link are empty, the platform shows "Coming to the App Store" or "Coming to Google Play". |
| `SUPPORT_EMAIL` | Shown on Support and Delete account |

### 2. Published content

This is the contract between the publish command (`tool/publish/` in
the Anchorline repository, PR #140), the site, and later the app's
update check. The cloud-builds spec §8 refers to it and does not restate
it. PR #140 amended the October spec's §2; those amendments are included
here.

**The bucket.** One public R2 bucket in Cloudflare's default
jurisdiction, written by the publish command and read by the site and
later by the app. Until the build pipeline exists, Egbert runs the
publish command by hand with an R2 key scoped to this bucket. Its public
address is a Cloudflare custom domain, planned `downloads.anchorline.eu`,
which is why the zone must sit in Cloudflare DNS. The bucket's
`pub-*.r2.dev` address is rate-limited and meant for development; it is
never linked from the site or written into a releases list. As of
2026-11-08 no downloads bucket exists (`wrangler r2 bucket list` shows
only the attachments and De Spaankamer buckets), so there is nothing to
migrate.

```
releases/
  manifest.json
  1.1.0/
    Anchorline-1.1.0-windows-x64.exe
    Anchorline-1.1.0-linux-x64.AppImage
nightly/                      (when nightlies exist)
  manifest.json
  1.3.0-157/
    Anchorline-Nightly-1.3.0-157-windows-x64.exe
    Anchorline-Nightly-1.3.0-157-linux-x64.AppImage
    Anchorline-Nightly-1.3.0-157-macos.dmg
content/
  index.json                  (title and last-updated date per text)
  legal/privacy.md
  legal/terms.md
  legal/account-deletion.md
  docs/user/index.md          (the manual's contents page)
  docs/user/<slug>.md         (one manual page per screen)
  docs/user/images/<slug>-<n>.png
```

**The releases list** (`releases/manifest.json`) carries a format
version:

```json
{
  "format": 1,
  "latest": {
    "version": "1.1.0",
    "build": 44,
    "date": "2026-11-07",
    "notes": "Markdown release notes",
    "files": {
      "windows-x64": {
        "url": "https://<downloads-host>/releases/1.1.0/Anchorline-1.1.0-windows-x64.exe",
        "size": 20971520,
        "sha256": "…"
      },
      "linux-x64": {
        "url": "https://<downloads-host>/releases/1.1.0/Anchorline-1.1.0-linux-x64.AppImage",
        "size": 18874368,
        "sha256": "…"
      }
    }
  },
  "previous": [ { "version": "1.0.0", "build": 40, "date": "…", "notes": "…", "files": { } } ]
}
```

Rules, as implemented in PR #140:

- `latest` is the highest version published, unless a roll back has
  made an earlier release `latest`. `previous` lists the others, newest
  first. A hotfix for an older line is listed in `previous`.
- A reader that meets a `format` it does not know treats the list as
  unavailable. New platforms are added as new keys under `files`;
  readers ignore keys they do not know and preserve them when rewriting.
- The nightly list (`nightly/manifest.json`) has the same shape, with a
  `macos` key next to `windows-x64` and `linux-x64`. A reader treats a
  nightly entry dated more than 14 days ago by UTC calendar date as
  unavailable. The R2 lifecycle rule on `nightly/` deletes files after
  15 days. Release files are kept.

**The content index** (`content/index.json`), my call on the shape since
PR #140 does not define it:

```json
{
  "format": 1,
  "texts": {
    "legal/privacy":          { "title": "Privacy policy", "updated": "2026-11-08", "path": "legal/privacy.md" },
    "legal/terms":            { "title": "Terms of service", "updated": "2026-11-08", "path": "legal/terms.md" },
    "legal/account-deletion": { "title": "Delete your account", "updated": "2026-11-08", "path": "legal/account-deletion.md" },
    "docs/user/index":        { "title": "Manual", "updated": "…", "path": "docs/user/index.md" },
    "docs/user/dives":        { "title": "Dives", "updated": "…", "path": "docs/user/dives.md" }
  }
}
```

For the legal texts the `updated` date is taken from the `_Last updated:
…_` line at the top of the file, so the date the visitor sees is the one
in the text, which is a legal statement. For manual pages it is the
file's last commit date, read from git by the publish command, so nobody
maintains dates by hand there. A manual page's `title` is its first
heading. Images are not listed; the Markdown references them by relative
path and the publish command uploads `docs/user/images/` next to the
pages.

**The publish command** (`tool/publish/publish.dart`, AWS CLI against
R2's S3 interface):

- `release`, `nightly`, `rollback`: as built in PR #140. Uploads,
  verifies every file's checksum by reading it back, writes the list
  last, refuses to overwrite a published version unless forced, treats
  an identical re-publish as a successful no-op.
- `content` (new, part of this work): uploads `docs/PRIVACY.md`,
  `docs/TERMS.md` and `docs/ACCOUNT_DELETION.md` to `content/legal/`,
  the manual (`docs/user/*.md` and `docs/user/images/`) to
  `content/docs/user/`, and regenerates `content/index.json`. It refuses
  to publish a manual page that references a missing image or an image
  without alternative text, and it removes manual pages and images from
  the bucket that no longer exist in the repository. Same dry-run mode
  and the same credentials-from-environment rule.
- A workflow in the Anchorline repository, `publish-content.yml`, runs
  the `content` action on every push to `main` that touches any of the
  three legal files or `docs/user/`, once the bucket and its secrets
  exist. It checks out the full history so the commit dates are right.
  Until then Egbert runs it by hand.

**How the site uses it**

- It fetches `releases/manifest.json`, `content/index.json` and the
  texts, manual pages included, from `DOWNLOADS_BASE_URL`, caches them
  in memory, and re-checks every five minutes. A failed re-check keeps the last good copy.
- The download page shows version, date, release notes, size and sha256
  per file, and the store links.
- Markdown is rendered to plain formatting only: headings, paragraphs,
  lists, emphasis, links, images, tables, block quotes. Raw HTML and
  scripts in a text are escaped, never rendered. Images are only ever
  loaded from `DOWNLOADS_BASE_URL` or the committed copy, never from a
  third host named in a text.
- Store links are site settings; they do not change per release.

**Fixture mode.** The site repository commits one fixture set under
`fixtures/`: a `releases/manifest.json` with the real 1.1.0 (build 44)
Windows and Linux file names, sizes and sha256 values from
`/Users/egbert/Dev/CCRLog/releases/1.1.0+44/SHA256SUMS`, with URLs
pointing at a placeholder downloads host; and `content/` with the three
legal texts, the manual with its screenshots, and their index, copied
from a checkout of the app repository by a script in the site repository
rather than edited by hand. The site serves this set at `/fixtures/`
and `DOWNLOADS_BASE_URL` defaults to it, so development, tests and the
first deploy all run against it. Switching to the real bucket is one
environment variable. In fixture mode the download page shows a small
"test build list" notice so nobody mistakes a placeholder link for a
download.

**When the bucket cannot be reached**

| Situation | What the visitor sees |
|---|---|
| Bucket briefly unreachable | The last version the site fetched |
| Site just restarted and the bucket is unreachable | The download page shows the store links and says the installers are temporarily unavailable |
| Malformed or unknown-format releases list | The same as unreachable |
| Legal and manual pages, in every case | Always shown. The site repository commits a copy of each text and screenshot (the same files as the fixture); it is served whenever the published copy is unavailable, with its own last-updated date |

**Security.** Only the publish command's key can write the bucket. The
site holds no secret; it reads public files. Each text carries a
last-updated date, and its history is in the Anchorline repository's
git log.

### 3. Look

- **Colours**, from `lib/ui/theme/anchorline_colors.dart` and the Wreck
  palette in `lib/ui/theme/tokens.dart`: hull black `#0A1419` as the
  page background, card `#142028` and raised `#1F2E38` for surfaces,
  reel orange `#C97B3A` for every call to action and nothing else,
  surface white `#E4E9E6` for text, `#A0AEB6` secondary, `#6B7D88`
  muted, slack-water steel `#3A6477` for borders and secondary accents.
  Chart colours in the live profile match the app: depth `#E0E8EC`,
  PPO₂ `#FFCC66`, setpoint `#A0AEB6` dashed, cells `#4ADE80`,
  `#60A5FA`, `#F472B6`.
- **Type**: Inter for text, JetBrains Mono with tabular figures for
  every number. Self-hosted font files, no third-party font service.
- **Marks**, from `assets/brand/`: the dark wordmark in the header, the
  inline orange anchor as favicon and in the footer, the full mark for
  social previews. Copied into the site repository; the app repository
  stays the source.
- **Tone**: the app's hard-edged instrument style. Flat surfaces, thin
  steel borders, no gradients, no illustration beyond the app's own
  screenshots and the live profile.
- Honours reduced-motion settings. Designed for phones first, since most
  visitors arrive from a store listing or a forum link.

### 4. Pages

#### 4.1 Home

In order, each section one screen or less on a phone:

1. **Hero.** Wordmark; one line, "Dive logging built for CCR." (Egbert
   may reword); two sentences: imports from a Shearwater over Bluetooth,
   and what the analysis shows (cell health, scrubber time, PPO₂ against
   setpoint). Three real screenshots from the current build in the
   Wreck theme at phone size, each inside a generic phone frame drawn by
   the site (rounded bezel, no manufacturer's device imagery). Below
   them the download row: the visitor's own platform first and in orange
   (the Windows installer or Linux AppImage with version and size, the
   matching store badge, or the "Join the beta" link while the store
   listing does not exist), the other platforms as smaller badges and
   links. Platform detection is client-side from the user agent; the
   server renders the neutral row first so nothing jumps.
2. **What it does today.** Six blocks, each a framed screenshot or the
   live profile next to a short text: the profile with PPO₂, setpoint and
   cells; deco replay with surface GF, CNS and OTU; cell mV history
   across dives; scrubber sessions; gas density and END; the blender and
   the planner. One line each on Subsurface import and the SOLO gas
   analyzer. The third block (the profile) is the live profile (§5). A
   "Read the manual" link closes the tour.
3. **Where it's going.** A short list with two labels, "next" for what
   is designed or being built and "exploring" for what is plausible but
   not promised. Initial content, Egbert's to edit: next — cell health
   across a cell's lifetime, two-way Subsurface sync, cloud sync across
   devices; exploring — other dive computers, the SOLO USB-to-Bluetooth
   bridge. A footnote says plans change and nothing here is a promise.
4. **Free and paid.** The app and all analysis, including cell health,
   are free. Cloud sync across devices, attachments and two-way
   Subsurface sync are the subscription. No prices on the site until
   they are set in the store consoles.
5. **Supported dive computers.** Shearwater Predator, Petrel 1, 2 and 3,
   NERD and NERD 2, Perdix, Perdix AI and Perdix 2, Teric, Peregrine and
   Peregrine TX, Tern, from `lib/shearwater/parser/hardware.dart`. One
   line that other manufacturers are not supported and that the source
   will be open for contributors to add them.
6. **Footer.** Open source (shown once the repository is public),
   Manual, Download, Privacy, Terms, Support, Delete your account, the
   publisher's name.

#### 4.2 Download

- Store badges for iOS, macOS and Android; while a store setting is
  empty, the "Join the beta" link or the "Coming to …" line from §1
  takes its place.
- Windows and Linux from the releases list: version, date, release notes
  rendered from Markdown, and per file the size and the sha256 with a
  copy button. The visitor's own platform is listed first.
- System requirements, as site content: iOS 15, macOS 12 (Subsurface
  Cloud sync needs macOS 26 on Apple Silicon), Android 7, Windows 10 or
  11 on x64, Linux x64 with glibc 2.35 or newer (Ubuntu 22.04 and
  later). To be re-checked at each release.
- A note under the Windows file: the installer is not yet signed, and
  Windows shows a "More info → Run anyway" step the first time.
- Release notes come from the list's `notes` field. For the fixture and
  for the first hand publish of 1.1.0 (build 44), the builder drafts the
  notes from the pull requests merged since the `v1.1.0` tag (whose own
  message describes only the June state) and Egbert edits them before
  they are published. Later releases take their notes from the annotated
  tag, as the cloud-builds spec says.
- "Previous versions" lists `previous` with the same fields, collapsed.
- In fixture mode, the notice described in §2.

#### 4.3 Privacy policy and terms

Rendered from the published Markdown as in §2, with the last-updated
date under the title and a line saying where the text's history can be
read once the repository is public. Markdown headings get stable
anchors, so `/privacy#deleting-your-account` works; the privacy policy
links to the account-deletion page.

#### 4.4 Delete your account

Rendered from `docs/ACCOUNT_DELETION.md` exactly like the other two
legal texts. Its content is owned by the in-app account-deletion work:
the in-app path (Settings → Sync → Delete account, type DELETE,
immediate), the email route for people without the app (confirmation
within five working days, completion within 30 days), what is deleted
and what stays, and re-signing up. Until that file exists the site's
committed fallback carries the same facts as the "Deleting your account"
section of `docs/PRIVACY.md`.

This page's address, `https://anchorline.eu/delete-account`, is the one
entered in Google Play's data-safety form and linked from the App Store
listing.

#### 4.5 Support

A pointer to the manual for questions about what a screen shows; the
support address; a short list of what to include in a problem report
(platform and version from Settings → About, the dive computer model,
what happened); and, once the repository is public, the link to the
issue tracker.

#### 4.6 Manual

A simple manual: one page per screen of the app, each with a screenshot
of that screen and a plain explanation of what it shows and what it is
for. Egbert asked for it on 2026-11-08; the shape below is my call.

**Where the text lives.** `docs/user/` in the app repository: `index.md`
is the contents page, one `<slug>.md` per screen, screenshots in
`images/<slug>-<n>.png`. Published to the bucket by the `content` action
(§2) and committed as a fallback in the site repository like the legal
texts. Keeping the pages next to the code means a PR that changes what a
screen shows can update the page and the screenshot in the same PR;
`CLAUDE.md` gets a line saying so when the first pages land.

**Contents page** (`/manual`, rendered from `index.md`). Two or three
sentences on what the manual is (it explains the app, not diving) and
the line "Written for Anchorline 1.1.0", then the pages grouped under
headings that match the app's bottom bar. The order of the links in
`index.md` is the reading order; the site derives the previous and next
links from it, so the order lives in one place.

**Initial page list**, from the app as of 1.1.0 (build 44). Egbert may
strike, merge or add. A screen that is only a list plus a detail view
shares one page.

| Group | Page (slug) | Screen(s) |
|---|---|---|
| Getting started | `getting-started` | First launch, the bottom bar, theme and units; where to go first |
| Dives | `dives` | The dive list: what a row shows, sorting, how multi-segment dives are grouped, filters |
| Dives | `dive-details` | Dive detail, Details tab: the profile with PPO₂, setpoint and cells, the crosshair, deco and surface GF, CNS, OTU, gas density and END, events; the full-screen chart |
| Dives | `dive-information` | Information tab: notes, buddies, site, conditions, rating; what you edit versus what the computer logged |
| Dives | `dive-media` | Media tab: attaching photos and files, the image and PDF viewers |
| Dives | `dive-equipment` | Equipment tab: linking cells, a scrubber session and cylinders to a dive |
| Dives | `sites-map` | The sites map and the location picker |
| Dives | `statistics` | The statistics screen |
| Dives | `buddies` | The buddies list |
| Plan | `plan` | The planner |
| Gas | `gas-blend` | Blend tab |
| Gas | `gas-analyse` | Analyse tab: connecting the SOLO analyzer, reading a mix, printing a label |
| Gas | `gas-log` | Log tab: the analysis log and its CSV export |
| Import | `import` | Pairing a Shearwater over Bluetooth, downloading dives, re-import, recent imports |
| Equipment | `equipment` | The Equipment landing: Dive Computers, O2 Cells, Scrubbers, Cylinders |
| Equipment | `dive-computers` | List and detail |
| Equipment | `o2-cells` | List and cell detail with the mV history across dives |
| Equipment | `scrubbers` | Scrubber sessions list and session detail |
| Equipment | `cylinders` | List and detail |
| Settings | `settings-general` | General tab |
| Settings | `settings-planning` | Planning tab |
| Settings | `settings-gas` | Gas tab |
| Settings | `settings-sync` | Sync tab: account, cloud sync, Subsurface Cloud, Reset local data, Delete account |
| Settings | `settings-about` | About tab: version and build for problem reports, licences |

**Page shape.** Every page follows the same pattern and stays under
about 300 words:

1. Title: the screen's name as the app shows it. Under it one line on
   how to get there ("Dives → tap a dive → Details").
2. The screenshot, one or two, inside the generic phone frame of §4.1;
   at the top on a phone, beside the text on a desktop.
3. "What it's for": one short paragraph.
4. "On this screen": a list; each item names an element in bold with the
   label the app uses, then one or two sentences on what it shows or
   does and whether the value comes from the dive computer or from you.
5. "Good to know", optional, at most three notes: limits, how OC differs
   from CCR on this screen, where the desktop layout differs.
6. Previous and next page, and back to contents.

Written in the second person and present tense, for a diver who knows
diving but not the app. No numbered callouts drawn on the screenshots,
since they break on every layout change: the text names the labels
instead. The manual explains the app and never gives diving advice; the
safety section of the terms applies.

**Screenshots** follow the Screenshots decision and §4.1: Egbert's own
logbook, anonymised, Wreck theme, phone size, PNG under 400 kB each
after optimisation, with alternative text that says what the screen
shows. The site serves them resized for the viewport. Where a screen
differs on a desktop, the phone picture is still the one shown and the
difference is a note.

**Who writes it.** The builder drafts every page from the running app
and the code and captures the screenshots; Egbert reads them in the app
repository, one docs-only PR per group in the table above so each read
stays short. The site renders whatever is published; a page that is not
yet written is simply not linked from `index.md`.

### 5. The live profile

One real dive, fixed, built into the site. A visitor moving a finger or
the mouse across it sees depth, PPO₂, setpoint and the three cell
voltages at that moment, like the app's crosshair. Under it a strip of
cell mV per dive over a cell's life, the differentiator, with one cell
visibly drifting.

- **Data.** A JSON file of one dive's samples and one cell's history,
  exported from the app's own parsed data by a small Dart script in the
  app repository (`tool/site_showcase/`), so the numbers are real and
  the export is repeatable. The dive is one of Egbert's own and the cell
  history comes from his own cells (his permission, 2026-11-08). The
  export strips date, location, notes, serial numbers and any user or
  buddy names. The builder picks a dive with a clear profile and a deco
  phase and shows it to Egbert before step 3 ships.
- **Rendering.** One React component drawing SVG; the crosshair follows
  pointer and touch events; no animation beyond the crosshair, and none
  at all under reduced motion. It renders the static chart on the server
  so the section is complete before JavaScript loads.
- **Size.** The JSON stays under 100 kB; samples are decimated to one
  per ten seconds for the site.

### 6. Testing

- Unit tests for reading the releases list: valid, malformed, missing,
  unknown format, unknown platform keys, a nightly entry older than 14
  days, a roll back where `latest` is not the highest version.
- Unit tests for the content index and the Markdown renderer, including
  that raw HTML and script tags come out escaped.
- A test that the legal pages render from the committed copy when the
  published copy is unavailable, with the right last-updated date.
- Unit tests for the manual: previous and next derived from the contents
  page's link order; a page whose screenshot is missing still renders
  its text and shows the alternative text in the frame; relative image
  links resolve to the published or the committed copy and never
  elsewhere.
- The `content` action's refusals (missing image, image without
  alternative text) are unit-tested in the app repository, in dry-run
  mode.
- A browser test (Playwright) that the download page lists the right
  file first per platform user agent and that every link on the site,
  the manual pages included, resolves against the fixture.
- A build-time check that every image has alternative text and that the
  home page passes an accessibility pass (axe) with no serious issues.
- Lighthouse on the home page on a phone profile: performance and
  accessibility at or above 90 before launch.
- A manual check on a phone and on a desktop before each rollout step.

### 7. Rollout

| Step | Result | Needs |
|---|---|---|
| 1 | Site repository with CI (type check, lint, tests), Docker image, deploy workflow; a styled empty site answering on `anchorline.despaankamer.nl` | Egbert: GitHub repository, deploy secrets, the Caddy block and reload step in SpaankamerWeb, the one-off server commands from the builder's checklist, the interim page redirect |
| 2 | Download, Privacy, Terms, Delete account and Support pages working against the fixture, with the fallback legal texts | The revised `docs/PRIVACY.md` and `docs/TERMS.md` merged |
| 3 | Home page with screenshots and the live profile | Screenshots from Egbert's logbook, anonymised; the showcase export; Egbert's look at the chosen dive |
| 4 | The manual: `docs/user/` written for 1.1.0 with screenshots, in the fixture, `/manual` answering on the temporary address | Egbert's logbook for the screenshots, as in step 3; his read of each group's PR in the app repository |
| 5 | Domain live; store listings updated | Egbert only; checklist below |

Steps 3 and 4 do not depend on each other and may run side by side;
step 5 waits for both.

**Step 5, Egbert's checklist**

- Nederhost: nameservers for `anchorline.eu` set to the Cloudflare zone's
  two names. Cloudflare DNS: `A @` and `A www` to the Hetzner box, DNS
  only. Email Routing on, `support@` forwarded; a `_dmarc` TXT record
  with `v=DMARC1; p=reject;`.
- SpaankamerWeb: the Caddy block for `anchorline.eu` with `www` redirect
  (PR, his OK; the reload step from step 1 makes it take effect); the
  interim redirect retargeted to `anchorline.eu`; the interim page files
  deleted.
- Site repository: `SITE_URL` set to `https://anchorline.eu`.
- R2, when the bucket is created: custom domain `downloads.anchorline.eu`;
  `DOWNLOADS_BASE_URL` set to it; the 1.1.0 files published with the
  publish command; the fixture notice disappears by itself.
- App Store Connect and Google Play: privacy policy URL
  `https://anchorline.eu/privacy`, support URL
  `https://anchorline.eu/support`, account-deletion URL
  `https://anchorline.eu/delete-account`.
- GitHub Pages (`ccrlogger-legal`): both pages replaced by a redirect to
  the new addresses, kept for a year, since store listings and emails
  pointed at them.
- Windows installer: `MyAppURL` and `MyAppPublisher` in
  `windows/installer/anchorline.iss` set to `https://anchorline.eu` and
  "Egbert De Pauw" for the next release.

## Companion work in the Anchorline app repository

- **Legal texts** (this PR): `docs/PRIVACY.md` renamed to Anchorline and
  revised, including the "Deleting your account" section;
  `docs/TERMS.md` drafted. Both marked for a legal read.
  `docs/ACCOUNT_DELETION.md` comes from the account-deletion work.
- **Publish command**: the `content` action and `publish-content.yml`
  (after PR #140 merges; small), covering the legal texts and the
  manual.
- **Manual** (step 4): `docs/user/` with the contents page, one page per
  screen and the screenshots, in docs-only PRs per group; a line in
  `CLAUDE.md` that a PR changing what a screen shows updates its manual
  page; later, a "User manual" link in Settings → About that opens
  `/manual`.
- **Showcase export**: `tool/site_showcase/` (step 3).
- **Update check on Windows and Linux**: unchanged from the October
  spec. At launch the app reads `releases/manifest.json` and, if
  `latest.version` is newer than its own, tells the user and links to
  the download page. Only in copies with `DISTRIBUTION_CHANNEL=website`;
  never blocks startup; silent on failure. Its own small piece of work
  once the bucket exists.
- **Installer strings**: see step 4.

## Later stages

- The nightly list on the download page, once nightlies are produced.
- Linux package managers; macOS on Homebrew (needs the Developer ID build
  and the web checkout, since in-app purchase works only in App Store
  builds).
- Manual search, translations and a PDF of the manual; an in-app help
  button per screen; account sign-in and subscription management on the
  site.
- Windows code signing (Microsoft Artifact Signing also validates
  individuals; the cloud-builds spec's "under De Spaankamer BV" becomes
  "under Egbert De Pauw").

## Open items

- **Support mailbox** must be receiving before the privacy policy and
  the store listings name it.
- **`anchorlineapp.com`**: register or drop.
- **Windows signing**: unchanged, a later stage.
- **Legal read** of the terms, with the trademark note.
