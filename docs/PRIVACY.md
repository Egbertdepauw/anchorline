# Anchorline Privacy Policy

_Last updated: 8 November 2026_

This policy explains what data Anchorline collects, why, where it goes,
and what you can do about it. It is written in plain English on purpose.
If anything here is unclear, email us (see **Contact**) and we will
clarify.

Anchorline is a dive-logging and analysis app for technical and
closed-circuit-rebreather divers. It runs on your phone or computer,
stores your dives on your device, and can optionally sync them to our
cloud so they are available on your other devices.

## Who is responsible

The data controller for Anchorline is:

> **Egbert De Pauw**
> The Netherlands
> support@anchorline.eu

Egbert De Pauw, an individual established in the Netherlands, acts as the
data controller under the EU General Data Protection Regulation (GDPR).

## In short

- We collect only what is needed to make the app work, to run the paid
  features, and to improve the app.
- We do not sell your data, show ads, or share data with advertisers,
  marketers or analytics brokers.
- You can use the app fully offline, without an account.
- All data we control is hosted in the European Union.
- You can delete your account yourself from inside the app, at once and
  completely, and your devices keep their copy of your dive log.

## What Anchorline collects, and why

### 1. Account information

If you create an account, which you only need for the paid cloud
features:

- **Email address.** Used to sign you in and to send account-related
  messages: password resets, security notices, subscription and
  data-retention reminders.
- **A randomly generated user ID.** Used to link your data to your
  account.

We do **not** collect your name, date of birth, address or phone number.

**Legal basis:** Article 6(1)(b) GDPR, necessary to provide the service
you asked for.

### 2. Dive data you record or enter

- Dive computer logs you import (Shearwater binary data and the
  per-sample values it contains: depth, time, temperature, PPO₂, cell
  voltages, setpoints, gases, deco information).
- Dive details you enter or edit: notes, buddy names, dive site,
  conditions, rating, equipment used.
- Approximate GPS coordinates of a dive site, only if you allow Location
  access and choose "use current location".
- Photos, PDFs or other files you attach to a dive.
- Gas analyses you record with a connected gas analyzer.

**Where it lives:** on your device, always. If you have signed in and
cloud sync is on, this data is also stored in our backend in the EU.

**Legal basis:** Article 6(1)(b) GDPR. You asked the app to store, and
optionally sync, your dive log.

### 3. Equipment data you record

Dive computers, cylinders, scrubbers, oxygen cells: serial numbers,
configuration and usage history. Same handling and legal basis as dive
data.

### 4. Subscriptions and payments

Cloud sync, attachments and two-way Subsurface sync are paid features.
How payment works depends on where you bought the app:

- **App Store, Mac App Store, Google Play.** Apple or Google handles the
  purchase and holds your payment details under its own privacy policy.
  We never see your card or bank details. We receive a confirmation that
  your account has a subscription, which plan, and until when.
- **Website (Windows and Linux).** The purchase is handled by Paddle, a
  merchant of record, which holds your billing details and issues the
  invoice. We receive the same confirmation as above.
- **Subscription processing.** We use RevenueCat to receive and store
  these confirmations across platforms. RevenueCat sees your random user
  ID and the purchase details, not your email.

We keep a record per account of whether it has access to the paid
features and until when.

**Legal basis:** Article 6(1)(b) GDPR, and Article 6(1)(c) for the
records tax law requires us to keep.

### 5. Crash reports

When the app crashes or hits an unexpected error in a release build, it
sends a crash report to **Sentry**, an error-tracking service, hosted in
the **European Union**. A report includes:

- a stack trace of the code path that failed;
- the device model and operating-system version;
- an anonymous installation identifier (a random per-install string,
  not linked to your account or email);
- the app version and build number.

It does **not** include your dive data, your email, or the contents of
any file you attached.

**Legal basis:** Article 6(1)(f) GDPR, our legitimate interest in keeping
the app stable and safe to use.

### 6. Usage statistics

The app records a small set of events into our own database, for
example "session started" with the platform name, "import completed"
with the number of dives, or "import failed" with a short error reason.
These events carry your account ID when you are signed in, so we can
tell five users apart from one user five times. They **never** contain
dive content, notes, locations or file contents. Their sole purpose is
to see which features divers actually use.

**Legal basis:** Article 6(1)(f) GDPR, our legitimate interest in
improving the app.

If you do not want to be counted, email us and we will delete all events
tied to your account. Deleting your account deletes them as well.

### 7. Map tiles

When you view a dive site on a map, Anchorline fetches map tiles from
**OpenStreetMap** or **Esri ArcGIS**, depending on the layer you choose.
Those providers see the approximate region you are looking at and your
IP address. We do not control them:

- OpenStreetMap: https://wiki.osmfoundation.org/wiki/Privacy_Policy
- Esri: https://www.esri.com/en-us/privacy/overview

### 8. Subsurface Cloud sync (optional)

If you set up Subsurface Cloud sync, your dive data, in the Subsurface
format, is exchanged with your own Subsurface Cloud account. Subsurface
Cloud is run by the Subsurface project and is **not** controlled by us.
We never see your Subsurface credentials; they are stored only in your
device's secure keychain.

### 9. Bluetooth and location permissions

The app asks for Bluetooth access to talk to your dive computer, a gas
analyzer or a label printer. On Android, older versions also require the
Location permission for Bluetooth scanning; we do not use it to locate
you. Nothing from these connections leaves your device except as
described under dive data.

### 10. The website

anchorline.eu sets no cookies and uses no analytics. Our web server
keeps ordinary access logs (IP address, requested page, time) for up to
14 days for security and troubleshooting. Downloads are served from
Cloudflare, which sees the IP address of the download.

## Where data is stored

- **On your device:** in Anchorline's app-private storage. It is not
  encrypted at rest beyond what the operating system provides.
- **In our cloud backend:** Supabase (Supabase Inc., EU region) for the
  database and sign-in; PowerSync (Journey Mobile, Inc.) for the sync
  service; Cloudflare R2 (Cloudflare, Inc.) for file attachments; Sentry
  (Functional Software, Inc.) in its EU region for crash reports;
  RevenueCat, Inc. for subscription records; Paddle.com Market Ltd for
  website purchases.
- Each provider processes data on our instructions under a data
  processing agreement, or, for Paddle, Apple and Google, as an
  independent controller for the payment itself.

## How long we keep data

- **Dive data, equipment data, attachments:** until you delete them in
  the app or delete your account.
- **After a subscription ends:** sync stops, but your devices keep their
  copies. The server copy is kept for 6 months so you can come back,
  with reminder emails before it goes, then deleted.
- **Crash reports:** 30 days, then deleted by Sentry.
- **Usage events:** as long as your account exists.
- **Subscription records:** as long as tax law requires, 7 years in the
  Netherlands.
- **Backups:** our database provider keeps routine backups for up to
  7 days; deleted data disappears from them after that.

## Deleting your account

You only have an account if you signed in for the paid cloud features.
Without one there is nothing to delete on our side; your dive log lives
only on your device.

**In the app.** Settings → Sync → Delete account, type DELETE to confirm.
Deletion is immediate. It removes, in one go:

| Deleted | Where |
|---|---|
| The account itself: email, password hash, sessions | Our sign-in service |
| Every synced dive, sample, annotation and equipment record | Our database |
| Every attachment you uploaded | Our file storage |
| Your subscription-access record and usage events | Our database |

What stays: crash reports, which cannot be matched to an account because
they carry only a random install identifier, and which expire after 30
days; aggregated counts that identify nobody; routine database backups,
which age out within 7 days; and records of past payments where tax law
requires us to keep them. Dives on your dive computer and in your own
Subsurface Cloud account are not affected.

Other devices signed in to the account are signed out within about an
hour. While they are online, the synced data disappears from them
through sync; their local copy of anything not synced stays.

**Without the app.** Email support@anchorline.eu from the address you
signed up with, subject "Delete my Anchorline account". We confirm within five
working days and complete the deletion within 30 days.

Deleting in the app also clears the device you delete from. Other
devices, and every device if you delete by email, keep their local copy
of anything not removed by sync; remove it with Settings → Sync → Reset
local data, or by uninstalling the app. Signing up again later with the
same email creates a new, empty account.

A standalone copy of these instructions is at
https://anchorline.eu/delete-account.

## Your rights (GDPR)

You have the right to:

- **Access** the personal data we hold about you.
- **Rectify** inaccurate data (most fields you can edit in the app).
- **Erase** your data, yourself in the app or by asking us; see
  "Deleting your account" above.
- **Restrict** or **object** to certain processing.
- **Portability**: on request we provide your account's data in a
  machine-readable format. If you use Subsurface Cloud sync, your dives
  are also in your own Subsurface account.
- **Withdraw consent** at any time where consent is the basis.
- **Complain** to the Dutch Data Protection Authority (Autoriteit
  Persoonsgegevens, https://autoriteitpersoonsgegevens.nl) or the
  authority in your own country.

To exercise any of these rights, email **support@anchorline.eu** from
the address you signed in with. We aim to respond within 30 days.

## Children

Anchorline is not directed at children under 16, and we do not knowingly
collect personal data from them. If you believe a child has given us
personal data, contact us and we will delete it.

## Security

- All communication between the app, the website and our backend uses
  HTTPS.
- Backend data is encrypted at rest by our providers.
- Subsurface Cloud credentials are stored in your device's secure
  keychain, never in plain text.

No system is perfectly secure. If you believe your account has been
compromised, email us immediately.

## App stores as distribution channels

Anchorline is distributed through Apple's App Store and TestFlight,
Google Play, and as a direct download from anchorline.eu. Apple and
Google receive metadata about your install (device model, OS version,
install and crash counts) under their own privacy policies:

- Apple: https://www.apple.com/legal/privacy/
- Google: https://policies.google.com/privacy

## Changes to this policy

We update this page when the way we handle data changes. The "Last
updated" date at the top reflects the most recent change. For material
changes we also notify signed-in users by email or in-app message.

## Contact

For any privacy question or to exercise your rights:

> **Egbert De Pauw**
> support@anchorline.eu
