# Anchorline website — design

Date: 2026-10-07
Status: design approved in conversation; awaiting spec review
Context: `docs/RELEASE_AND_MONETISATION.md`

The website is its own project in its own repository. This spec lives in
the Anchorline app repository for now because two of its parts are built
here: the publish command and the releases list the app will read.

## Goal

A public website for Anchorline that presents the product, offers the
Windows and Linux downloads, links to the app stores, and hosts the
legal pages the stores require, with new builds and texts published
straight from the Anchorline repository.

Success means:

- A visitor understands what Anchorline is and can get it for their
  platform within one screen.
- Publishing a new build or a changed legal text needs one command in
  the Anchorline repository, no change to the site's repository and no
  site deploy.
- The privacy policy and terms are always reachable.
- The site cannot affect De Spaankamer's site, with which it shares a
  server.

## Decisions

| Question | Decision |
|---|---|
| First version's scope? | Landing page, store links, Windows and Linux downloads, privacy policy, terms, support contact |
| Where is it hosted? | Next.js on the existing Hetzner server |
| Where does the code live? | Its own repository and its own app on the server |
| How is content updated? | Published from the Anchorline repository to a shared bucket the site reads |
| Where do installer files live? | Cloudflare R2, linked from the site |
| Languages? | English only, built so more can be added |
| Domain? | Not yet owned. Must be registered before going live and before the store submissions |

## Out of scope for the first version

- Account sign-in and subscription management on the site. Wanted
  later; the structure leaves room for it.
- Documentation pages. The publishing route carries them; the pages
  follow when the texts exist.
- Newsletter, blog, analytics.
- Linux distribution packages (Debian, Fedora, Arch and others) and a
  macOS Homebrew build. Both are later stages (see "Later stages").

## Design

### 1. Structure and stack

**Pages**

| Page | Content | Source |
|---|---|---|
| Home | What Anchorline is, who it is for, the differentiators with a live showcase, store badges, download button | Site repository |
| Download | Store links for iOS, macOS and Android; current Windows and Linux installers with version, date, release notes and checksums | Published content |
| Privacy policy | | Published content |
| Terms | Including the subscription terms | Published content |
| Support | Contact address and where to report a problem | Site repository |

**Stack.** The same as De Spaankamer's site, so nothing new to learn:
Next.js 16 with the same styling tools, built into a Docker image by a
GitHub Actions workflow, published to GitHub's container registry, and
run with Docker Compose on the Hetzner server behind the existing web
front end, answering on the Anchorline domain.

**What it does not have.** No database, no content-management system,
no logins. One container with no state of its own; it can be rebuilt or
moved without losing anything.

**Isolation.** Its own repository and deploy workflow, so a failed
deploy of either site cannot touch the other. The container runs with a
memory limit so it cannot starve its neighbour.

**The domain is one setting** in the site and one in the Anchorline
repository's publish configuration. Everything is built and tested on a
temporary address first.

### 2. Published content

**The bucket.** One public R2 bucket, written only by the build
pipeline with an R2 key that is scoped to this bucket (the owner can run
the publish command by hand in an emergency), read by the site and later
by the app.

```
releases/
  manifest.json
  1.2.0/
    Anchorline-1.2.0-windows-x64.exe
    Anchorline-1.2.0-linux-x64.AppImage
nightly/
  manifest.json
  1.3.0-157/
    Anchorline-Nightly-1.3.0-157-windows-x64.exe
    Anchorline-Nightly-1.3.0-157-linux-x64.AppImage
    Anchorline-Nightly-1.3.0-157-macos.dmg
content/
  legal/privacy.md
  legal/terms.md
  docs/...            (later)
  index.json          (title and last-updated date per text)
```

**The releases list** (`releases/manifest.json`) is a contract between
the publish command, the site and the app, so it carries a format
version:

```json
{
  "format": 1,
  "latest": {
    "version": "1.2.0",
    "build": 45,
    "date": "2026-11-03",
    "notes": "Markdown release notes",
    "files": {
      "windows-x64": {
        "url": "https://<downloads-host>/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe",
        "size": 48211200,
        "sha256": "…"
      },
      "linux-x64": {
        "url": "https://<downloads-host>/releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage",
        "size": 51380224,
        "sha256": "…"
      }
    }
  },
  "previous": [ { "version": "1.1.0", "build": 41, "date": "…", "files": { } } ]
}
```

`latest` is the highest version published, unless a roll back has made
an earlier release `latest`. `previous` lists the others, newest first.
A hotfix for an older line (1.1.1 while 1.2.0 is the latest) is listed
in `previous` and does not become `latest`.

A reader that meets a `format` it does not know treats the list as
unavailable. New platforms are added as new keys under `files`; readers
ignore keys they do not know.

**The nightly list** (`nightly/manifest.json`) has the same format-1
shape. Its entries carry a `macos` key (the `.dmg`) next to
`windows-x64` and `linux-x64`. A nightly is offered for 14 days. The
publish command drops older entries from the list, but only when it
publishes, and nightlies are only built when main has changed. So the
list alone does not keep an old entry out, and the rule is part of the
contract: **a reader (the site and the app) treats a nightly entry dated
more than 14 days ago by UTC calendar date as unavailable.** When main
has been quiet that long there is simply no nightly to download. The R2
lifecycle rule on the `nightly/` prefix deletes files after 15 days, one
day longer, so a nightly that is listed and offered never points to a
deleted file. Release files are kept.

**Sources in the Anchorline repository**

| Published | Source |
|---|---|
| Privacy policy | `docs/PRIVACY.md` (exists) |
| Terms | `docs/TERMS.md` (to be written) |
| Documentation, later | `docs/user/` |

**The publish command.** A script in the Anchorline repository, at
`tool/publish/`. It uses the AWS CLI against R2's S3 interface. That
replaces the earlier idea of the Cloudflare `wrangler` tool, because
the AWS CLI is preinstalled on GitHub's runners. Its actions:

- **Publish a release**: takes a version, a build number, the installer
  files (a release needs both `windows-x64` and `linux-x64`) and a
  release-notes file. It computes sizes and checksums, uploads the
  files, verifies each upload, and only then replaces `manifest.json`.
  The highest version becomes `latest` and the old `latest` moves into
  `previous`. It refuses to overwrite an existing version unless told
  to, with one exception: publishing the identical files again for the
  same version and build is a no-op that succeeds ("already published,
  nothing to do"), so a re-run of the build pipeline finishes. Different
  files are refused unless told to. Older versions stay in the bucket.
- **Publish a nightly**: the same steps for a nightly, with a version
  and a build number, into `nightly/manifest.json` and
  `nightly/<version>-<build>/`. It refuses a build number that is
  already listed, except for the identical files again, which is the
  same no-op that succeeds; a nightly cannot be forced. It drops entries
  older than 14 days.
- **Roll back**: makes a previous release `latest` again by replacing
  `releases/manifest.json`. Nothing is deleted.
- **Publish content**: uploads the legal and documentation texts and
  regenerates `content/index.json`.

Each has a dry-run mode that prints what would change.

**How the site uses it**

- It fetches `manifest.json`, `index.json` and the texts from the bucket
  and re-checks every five minutes.
- The download page shows version, date, release notes and each file's
  checksum.
- A nightly entry dated more than 14 days ago by UTC calendar date is not
  offered.
- Markdown is rendered to plain formatting only. Raw HTML and scripts in
  a text are not rendered.
- Store links for iOS, macOS and Android are site settings; they do not
  change per release.

**When the bucket cannot be reached**

| Situation | What the visitor sees |
|---|---|
| Bucket briefly unreachable | The last version the site fetched |
| Site just restarted and the bucket is unreachable | The download page shows the store links and says the installers are temporarily unavailable |
| Malformed or unknown-format releases list | The same as unreachable |
| Legal pages, in every case | Always shown. Each site image is built with a copy of the legal texts as a fallback |

**Security.** Only the build pipeline can write to the bucket, with an
R2 key that is scoped to this bucket; the owner can run the publish
command by hand in an emergency. The site holds no secret; it reads
public files. Each legal text carries a last-updated date, and its
history is in the Anchorline repository's git log.

### 3. Look, content and rollout

**Look and feel**

- The app's identity: the dark Wreck palette, the orange accent, Inter
  and JetBrains Mono, the hard-edged instrument style.
- The engaging element is real analysis on the home page: a dive profile
  with PPO2 and cell traces that responds as the visitor moves across
  it, and a cell-health trend. It uses fixed sample data built into the
  site.
- It honours reduced-motion settings and is designed for phones first,
  since many visitors arrive from a store listing.

**Home page, in order**

1. What it is and who it is for, with store badges and the download
   button.
2. The differentiators: cell health over a cell's lifetime, scrubber
   tracking, the profile with PPO2 and setpoint.
3. What is free and what the subscription adds.
4. Open source: why, and how to help add a dive computer. Shown once the
   repository is public.
5. Supported dive computers.

**Testing**

- Automated tests for reading the releases list: valid, malformed,
  missing, unknown format, unknown platform keys.
- A test that the legal pages render from the built-in fallback when the
  bucket is unreachable.
- A browser test that the download page offers the right file per
  platform and that every link resolves.
- The publish command is tested in dry-run mode and against a scratch
  bucket before it touches the real one, including the refusal to
  overwrite and the manifest-last ordering.
- A manual check on phone and desktop before launch.

**Rollout**

| Step | Result | Needs the domain? |
|---|---|---|
| 1 | Site repository, deploy workflow, an empty styled site on a temporary address | No |
| 2 | Bucket and publish command; download and legal pages working from published content | No |
| 3 | Home page with the live showcase | No |
| 4 | Domain registered and pointed at the site; store listings updated with the privacy and support addresses | Yes |

## Companion work in the Anchorline app

Its own small piece of work, after the publish command exists.

**Update check on Windows and Linux**

- At launch the app reads `manifest.json` and, if `latest.version` is
  newer than its own, tells the user and links to the download. It does
  not download or replace itself.
- Settings gets a "Check for updates" button that does the same on
  demand and reports "up to date" otherwise.
- A failed or slow check never delays or blocks startup, and is silent
  at launch.
- The check runs only in copies that came from the website. The app
  knows how it was distributed through a build-time setting (website,
  App Store, Play Store, and later Homebrew or a Linux package manager).
  Store and package-manager copies leave updating to their channel.

The same build-time setting decides how a subscription is bought; see
the subscriptions and entitlements spec.

## Later stages

- **Linux package managers.** Debian, Fedora, Arch and similar. The
  first version ships one self-contained download.
- **macOS on Homebrew.** This needs a directly downloaded, notarised
  macOS build, distinct from the Mac App Store build. Apple's in-app
  purchase works only in App Store builds, so a Homebrew copy buys
  through the web checkout.
- **Documentation pages**, **account sign-in on the site**.

## Open items

- **Domain.** Not yet owned. A DNS check on 2026-10-07 found
  `anchorline.com`, `.app`, `.io`, `.org`, `.dev` and
  `getanchorline.com` taken, and `anchorline.eu`, `anchorline.nl`,
  `anchorlineapp.com` and `anchorlinelog.com` possibly free. To be
  confirmed at a registrar. A trademark search for the name is advisable
  before investing in the brand.
- **Terms.** `docs/TERMS.md` does not exist. It needs writing and is
  worth a legal read, since it carries the subscription terms.
- **Windows code signing.** Unsigned installers trigger a security
  warning. A certificate is a recurring fee, not yet priced.
- **Needed before rollout step 4:** the domain, the terms, and the
  Windows signing decision.
