# CCRLog Privacy Policy

_Last updated: 19 May 2026_

This policy explains what data CCRLog collects, why, where it goes, and what
you can do about it. It is written in plain English on purpose — if anything
here is unclear, please email us (see the **Contact** section) and we will
clarify.

CCRLog is a dive-logging app for technical and closed-circuit-rebreather
divers. It runs on your phone or computer, stores your dives locally, and
optionally syncs them to the cloud so they are available on your other
devices.

## Who is responsible

The data controller for CCRLog is:

> **Egbert De Pauw**
> The Netherlands
> egbert.de.pauw@gmail.com

CCRLog is currently a privately-run beta. Egbert De Pauw, an individual,
acts as the data controller under the EU General Data Protection
Regulation (GDPR).

## TL;DR

- We collect only what is needed to make the app work and to improve it.
- We do not sell your data.
- We do not show ads.
- We do not share data with advertisers, marketers, or analytics brokers.
- You can use the app fully offline if you prefer (no account, no cloud).
- All data we control is hosted in the European Union.
- You can ask us at any time to export or delete your data.

## What CCRLog collects, and why

### 1. Account information

If you sign in to enable cloud sync:

- **Email address.** Used only to authenticate you and to send
  account-related messages (password reset, security notices).
- **A randomly-generated user ID.** Used to link your data to your
  account.

We do **not** collect your name, date of birth, address, or phone
number.

**Legal basis:** Article 6(1)(b) GDPR — necessary for performance of the
service.

### 2. Dive data you record or enter

- Imported dive computer logs (Shearwater binary blobs and the parsed
  per-sample data they contain).
- Dive metadata you enter or edit: notes, buddy names, dive site,
  conditions, rating, divemaster, equipment used.
- Approximate GPS coordinates of the dive site, if you allow Location
  access and tap "use current location."
- Photos, PDFs, or other files you attach to a dive.

**Where it lives:** locally on your device at all times. If you have signed
in and cloud sync is enabled, this data is also stored in our backend in
the EU.

**Legal basis:** Article 6(1)(b) GDPR — you asked the app to store and sync
your dive log.

### 3. Equipment data you record

- Dive computers, cylinders, scrubbers, oxygen cells. Serial numbers,
  configuration, usage history.

Same handling and legal basis as dive data above.

### 4. Crash reports

When the app crashes or an unhandled exception occurs in a release
build, we send a crash report to **Sentry**, a third-party error-tracking
service, hosted in the **European Union**.

A crash report includes:

- A stack trace of the code path that failed.
- The model and OS version of the device.
- An anonymous installation identifier (a random per-install string,
  not linked to your account or your email).
- The app version and build number.

It does **not** include your dive data, your email, or the contents of
any file you have attached.

**Legal basis:** Article 6(1)(f) GDPR — legitimate interest in keeping
the app stable and safe to use.

### 5. Anonymous usage statistics

The app records a small set of events (which features you used, and
when) into our own database. Examples:

- "Session started" with the platform name (iOS, Android, macOS).
- "Import completed" with the count of dives downloaded.
- "Import failed" with a short error reason.

These events include your account ID so we can tell whether 5 users
imported once or 1 user imported 5 times — but **they never contain dive
content, notes, locations, file contents, or any other personal
detail**. Their sole purpose is to help us understand which features
divers actually use so we can prioritise improvements.

**Legal basis:** Article 6(1)(f) GDPR — legitimate interest in product
improvement.

If you do not want to be counted in these statistics, email us (see
**Your rights** below) and we will delete all events tied to your
account.

### 6. Map tile requests

When you view a dive site on a map, CCRLog fetches map tiles from
**OpenStreetMap** or **Esri ArcGIS** (depending on the layer you
select). Those providers see the approximate geographic region you are
looking at and your IP address. We do not control those providers and
cannot speak to their retention. Their privacy policies:

- OpenStreetMap: https://wiki.osmfoundation.org/wiki/Privacy_Policy
- Esri: https://www.esri.com/en-us/privacy/overview

### 7. Subsurface Cloud sync (optional)

If you configure Subsurface Cloud sync in CCRLog, your dive data — in
the Subsurface git format — is pushed to your own Subsurface Cloud
account. Subsurface Cloud is operated by the Subsurface project and is
**not** controlled by us. Their privacy practices apply once data
leaves your device. We never see your Subsurface credentials; they are
stored only in your device's secure keychain.

## Where data is stored

- **On your device:** in CCRLog's app-private storage. Other apps
  cannot read it. This data is not encrypted at rest beyond what the
  operating system provides.
- **In our cloud backend:** Supabase (Supabase Inc., **EU region**),
  Cloudflare R2 (Cloudflare Inc., used for file attachments), and
  Sentry (Functional Software Inc. d/b/a Sentry, **EU region**).
- All three providers have signed GDPR Data Processing Agreements and
  are bound to handle data on our instructions only.

## How long we keep data

- **Dive data, equipment data, attachments:** until you delete it from
  the app or delete your account.
- **Crash reports:** Sentry retains them for 30 days (free tier) before
  automatic deletion. We may upgrade this period if we move to a paid
  plan.
- **Anonymous usage events:** retained as long as your account exists.
  Deleted when your account is deleted.
- **Account record itself:** until you ask us to delete it.

## Your rights (GDPR)

Under GDPR you have the right to:

- **Access** the personal data we hold about you.
- **Rectify** inaccurate data (most fields you can edit yourself in the
  app).
- **Erase** your data ("right to be forgotten").
- **Restrict** or **object** to certain processing.
- **Portability** — receive your dive data in a structured, commonly-used
  format. CCRLog supports export to Subsurface XML and UDDF formats from
  Settings.
- **Withdraw consent** at any time where consent was the basis.
- **Lodge a complaint** with the Dutch Data Protection Authority
  (Autoriteit Persoonsgegevens, https://autoriteitpersoonsgegevens.nl).

To exercise any of these rights, email **egbert.de.pauw@gmail.com**.
We aim to respond within 30 days.

## Children

CCRLog is not directed at children under the age of 16. We do not
knowingly collect personal data from under-16s. If you believe a child
has provided personal data to us, please contact us and we will delete
it.

## Security

- All communication between the app and our backend uses HTTPS / TLS.
- Backend data is encrypted at rest by our providers.
- Subsurface Cloud credentials are stored in your device's secure
  keychain, never in plain text.

No system is perfectly secure. If you believe your account has been
compromised, please email us immediately.

## Apple and Google as distribution channels

CCRLog is distributed via Apple's TestFlight (and later the App Store
and Google Play). These platforms receive metadata about your install
(device model, OS version, install / crash counts) under their own
privacy policies, which we do not control:

- Apple: https://www.apple.com/legal/privacy/
- Google: https://policies.google.com/privacy

## Changes to this policy

We will update this page when the way we handle data changes. The
"Last updated" date at the top reflects the most recent change. For
material changes we will additionally notify signed-in users by email
or in-app message.

## Contact

For any privacy question or to exercise your rights:

> **Egbert De Pauw**
> egbert.de.pauw@gmail.com
