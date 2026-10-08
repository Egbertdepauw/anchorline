# Anchorline — release and monetisation

Status: decisions recorded 2026-10-07, updated 2026-10-08. No part of this is
implemented yet.
Each piece of work listed under "Work breakdown" gets its own design and
plan before any code.

## Goal

Release Anchorline publicly and recover its running costs: hosting,
Cloudflare, the app stores, PowerSync and similar. The aim is to cover
costs, especially once usage outgrows the free tiers, with a modest
income beyond that as a bonus. It is not to maximise revenue.

Anchorline stays open source, for two reasons:

- **Other dive computers.** Only Shearwater computers are supported
  today. Supporting other technical dive computers needs contributors who
  own them.
- **Community.** Divers helping each other out. The paid part is only the
  part that costs money to run.

## Decisions

### What is free and what is paid

| Feature | Free | Paid subscription |
|---|---|---|
| The app itself | ✓ | |
| Import from the dive computer | ✓ | |
| All analysis, including cell health and other safety analysis | ✓ | |
| Export | ✓ | |
| One-way import from Subsurface | ✓ | |
| Anchorline cloud sync across devices | | ✓ |
| Attachments | | ✓ |
| Two-way sync with Subsurface | | ✓ |

Notes:

- **Safety analysis is never paywalled.** Cell-health trends are the
  app's differentiator and its reason to exist.
- **Two-way Subsurface sync is paid although it costs nothing to run.**
  It works on the user's device against Subsurface's servers. It is paid
  because it would otherwise be a free substitute for Anchorline's own
  sync. It is only a partial substitute: Subsurface's format does not
  carry Anchorline-specific data such as cell history, scrubber sessions
  or attachments.
- **That paywall is honour-system.** In an open-source app anyone can
  build a copy with a client-side check removed. Anchorline sync and
  attachments are different: they need Anchorline's servers, so the
  server can enforce payment.

### Distribution channels

| Platform | Channel | Payment |
|---|---|---|
| iOS | App Store | In-app purchase |
| macOS | Mac App Store | In-app purchase |
| Android | Google Play | In-app purchase |
| Windows | Website download | Web checkout |
| Linux | Website download | Web checkout |

Apple and Google require their own in-app purchase for subscriptions
bought inside store apps, and take 15% under their small-business
programmes. Website sales avoid that cut; a merchant-of-record service
can handle EU VAT.

### Hosting: staged, hosted-first

1. Launch on the free tiers, with sync as the paid subscription.
2. Move to Supabase Pro before or at the first paying subscriber, for
   the larger compute size and to stop the replication-slot stalls seen
   on the smallest size.
3. Stay on free PowerSync until usage approaches 50 concurrent clients or
   500 MB hosted, then choose between PowerSync Pro and self-hosting
   PowerSync's free Open Edition on the existing Hetzner server, using
   real numbers.

Long-term advice: stay hosted. Self-hosting would save at most the
hosted fees (about €910 a year at the full hosted stack) and would mean
running and backing up the database for people's dive logs alone.
Revisit only past a couple of thousand subscribers or if pricing
changes.

### Licence: GPLv2

GPLv2, with three additions:

1. **An App Store exception.** An added permission allowing distribution
   through app stores, which contributors accept when they contribute.
   GPL and Apple's store terms are a known grey area; the owner can
   publish their own code, the question is other people's contributions.
2. **Developer Certificate of Origin sign-off** for contributions, not a
   heavyweight contributor agreement, to keep the barrier low.
3. **Name and logo excluded.** "Anchorline" and the brand assets are not
   covered by the licence, so a fork must use its own name.

Why GPLv2 and not something else:

- Contributors can borrow from the existing dive-software ecosystem:
  libdivecomputer (LGPL) and Subsurface (GPLv2). Code from both can go
  into a GPLv2 project.
- AGPLv3 was the other candidate and is ruled out: Subsurface's GPLv2
  code is not compatible with version 3 licences.
- A permissive licence (MIT, Apache) would be simpler for the stores but
  would not allow ported Subsurface code and would permit closed forks.
- It keeps contributions open and does not get in the way of selling the
  hosted service.

Facts that bear on this, as of 2026-10-07:

- The repository is private and has no `LICENSE` file.
- The Shearwater parser states in its own comments that it is ported
  from libdivecomputer (`lib/shearwater/parser/dive_parser.dart`,
  `decompressor.dart`, `constants.dart`, `hardware.dart`).
- `lib/analysis/deco/tissue_model.dart` takes its ZHL-16C constants from
  Subsurface's `core/deco.cpp`.
- For the libdivecomputer-derived parts, an App Store exception cannot be
  added on the original author's behalf. Subsurface-mobile ships the same
  code on the App Store, so this follows existing practice.

**How Subsurface handles the App Store** (looked into on 2026-10-08):

- Subsurface is GPLv2, its libdivecomputer copy is LGPL 2.1, and
  Subsurface-mobile is on the iOS App Store built from both. Its README
  states the licence and says nothing about iOS, the App Store or any
  exception.
- No documented legal mechanism was found. They publish it, and nobody
  with a claim objects. Apple does not police this conflict; a problem
  arises only when a copyright holder complains. The known case is VLC,
  which was pulled from the store after one of its own contributors
  objected and returned after relicensing.
- For Anchorline: the owner's code can be published anywhere,
  contributors' code is covered by the App Store exception, and the
  remaining exposure is the code ported from libdivecomputer, whose
  author could object in principle. Subsurface-mobile has shipped his
  library on the store for years, so this is unlikely, but it rests on
  tolerance and not on permission.
- A cheap way to firm it up: ask libdivecomputer's author directly
  whether he is comfortable with it. His goodwill matters anyway once
  other dive computers are supported.

Sources: [Subsurface on GitHub](https://github.com/subsurface/subsurface),
[Subsurface-mobile on the App Store](https://apps.apple.com/us/app/subsurface-mobile/id1093217161),
[discussion of GPL and the App Store](https://news.ycombinator.com/item?id=20050952).

This is not legal advice. The App Store exception is the one point where
an hour of paid legal advice is worthwhile before the public release.

## Costs

### Today

Every service is on its free tier. The only running cost is Hetzner,
€ 19.07 a month, which is shared with De Spaankamer's website and
would be paid anyway. Apple's developer programme is $ 99 a year.

### Where the free tiers end

Limits and prices as published on 2026-10-07:

| Service | Free limit that matters | Next step up |
|---|---|---|
| Supabase | 500 MB database, 5 GB egress, pauses after 1 week of inactivity | Pro: $25/month (8 GB disk, 250 GB egress, Micro compute) |
| PowerSync | 500 MB hosted, 2 GB synced per month, 50 concurrent clients, deactivated after 1 week of inactivity | Pro: from $49/month (10 GB hosted, 30 GB synced, 1,000 concurrent; then $1 per GB) |
| Cloudflare R2 | 10 GB storage, egress free | $0.015 per GB-month |
| Cloudflare Workers | 100,000 requests per day | $5/month |
| Sentry | 5,000 errors per month, one user | Team: $26/month |

Sources: [Supabase](https://supabase.com/pricing),
[PowerSync](https://www.powersync.com/pricing),
[R2](https://developers.cloudflare.com/r2/pricing/),
[Workers](https://developers.cloudflare.com/workers/platform/pricing/),
[Sentry](https://sentry.io/pricing/).

**Database size is not the first limit after all.** `dive_samples` is
the heaviest table, but measurement on 2026-10-08 (below) puts a dive at
about 5 kB across the dive tables, so a diver with 200 dives takes
roughly 1 MB. The 500 MB limits then hold on the order of 200 to 450
syncing accounts, depending on how many dives each has. The first
estimate, made from the sample format before measuring, was 4 to 12 MB
per diver and 50 to 120 accounts; it was four to ten times too high.
PowerSync's limit of 50 concurrent clients is now the more likely first
ceiling.

To measure table sizes again, run in the Supabase SQL editor:

```sql
select relname, pg_size_pretty(pg_total_relation_size(relid))
from pg_catalog.pg_statio_user_tables
order by pg_total_relation_size(relid) desc limit 10;
```

Two points beyond the raw limits:

- The free tiers are not fit for paying customers: idle projects are
  paused, and the smallest compute size is where the stalls happen.
- Because sync is the paid feature, only paying users consume these
  limits. Free users cost nothing.

**Measured on 2026-10-08.** The whole database is about 10 MB, 2% of the
500 MB limit:

| Table | Size |
|---|---|
| `dive_samples` | 5264 kB |
| `cron.job_run_details` | 2584 kB |
| `dives` | 752 kB |
| `dive_annotations` | 592 kB |
| `usage_events` | 264 kB |
| `dive_attachments` | 168 kB |

- These sizes hold 1,256 dives from 3 accounts. That is 4.2 kB of
  samples per dive, and 5.3 kB per dive across `dive_samples`, `dives`
  and `dive_annotations`: about 1 MB for a diver with 200 dives, and
  2.2 MB for the average account here (about 420 dives).
- Caveats: three accounts is a small sample; table sizes include indexes;
  and PowerSync counts its hosted data in its own way, which may come
  out larger than the Postgres size. Check PowerSync's dashboard figure
  before relying on this for its 500 MB limit.
- `cron.job_run_details` is the run log of the job that clears stale
  replication slots every 15 minutes. Nothing deletes from it, so it
  grows by about a hundred rows a day. Clean-up is tracked in issue #98.

### The inactivity pause

Supabase pauses a free project that gets too little database activity
over 7 days; its documentation says a few user requests a day are
enough, and a paused project can be restored for 90 days. PowerSync
deactivates idle free instances as well; what counts as activity there
was not confirmed.

- Real use keeps both awake. The risk is a quiet stretch.
- A daily keep-alive request from the Cloudflare Worker covers that at
  no cost. Tracked in issue #98. It leans on a free tier's goodwill, so
  it is temporary.
- Supabase Pro does not pause, and is already the plan at the first
  paying subscriber.

Source: [Supabase project pausing](https://supabase.com/docs/guides/platform/free-project-pausing).

### Break-even

Assumptions: 21% Dutch VAT included in the price, a 15% store cut, and
$1 = €0.92. Hetzner is left out because it is paid anyway.

At €25 a year (about €17.50 net per subscriber):

| Stage | Monthly cost | Subscribers to break even |
|---|---|---|
| Free tiers plus Apple's developer fee | about €8 | 5 |
| Supabase Pro | about €31 | 21 |
| Supabase Pro and PowerSync Pro | about €76 | 52 |

Hosting as a share of revenue on the full hosted stack, at €25 a year:

| Paying subscribers | Net revenue per year | Hosting per year | Share |
|---|---|---|---|
| 50 | about €875 | about €910 | break-even |
| 200 | about €3,500 | about €910 | 26% |
| 500 | about €8,750 | about €910 | 10% |

## Pricing (not yet decided)

€25 a year is probably low for this audience, who spend thousands on a
rebreather and replace oxygen cells yearly. Suggested: test €39 to €49 a
year with a monthly option around €4.99. At €45 the net is about €31.50
per subscriber: break-even on the full hosted stack at about 30
subscribers, and about €15,750 a year at 500.

Expectation: a small niche. No reliable figure for the number of
technical and CCR divers using Shearwater computers was found, so no
market size is assumed. Realistically this covers costs quickly and can
become a modest side income.

## Work breakdown

Each gets its own design and plan. Subscriptions and entitlements is
designed first (`docs/superpowers/specs/2026-10-07-subscriptions-entitlements-design.md`).
The website is important and starts as its own project as soon as
possible, alongside the rest, not after it.

1. **Subscriptions and entitlements** (first). Where the "has paid" state
   lives; how the server enforces it for sync and attachments; in-app
   purchase on iOS, macOS and Android; web checkout for Windows and
   Linux; what happens to a user's data when a subscription lapses.
2. **Open-sourcing the repository.** Licence, App Store exception,
   contributor rules, proper credit for libdivecomputer- and
   Subsurface-derived code, and a scan of the git history for secrets
   before the repository goes public.
3. **Store releases.** Largely prepared (`docs/APP_STORE_SUBMISSION.md`,
   `docs/BETA_DISTRIBUTION.md`, signing). New: the review requirements
   that come with subscriptions and accounts.
4. **Website and downloads.** Landing page, Windows installer, Linux
   packages, web checkout.
5. **Backend scaling**, when the numbers call for it.

## Open questions

- The subscription price. Yearly and monthly plans are decided; the
  amounts are not.
- A domain for the website. None is owned yet; it is needed before going
  live and before the store submissions.
- The terms of service, including the subscription terms. Not yet
  written.
- Windows code signing: unsigned installers trigger a security warning,
  and a certificate is a recurring fee. Not yet priced.
- Legal review of the App Store exception, and whether to ask
  libdivecomputer's author about App Store distribution.
- A trademark search for the name "Anchorline".

Decided since this list was first written, and recorded in the
subscriptions and entitlements spec: what happens when a subscription
lapses, how beta testers are treated, the trial, and the plans.

## Later options (not planned)

- A plan for instructors or dive centres who follow students' logs.
- Paid storage tiers for heavy photo and video attachments.
