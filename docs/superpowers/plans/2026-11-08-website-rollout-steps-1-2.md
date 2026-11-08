# Anchorline Website, Rollout Steps 1 and 2: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A styled Anchorline site answering on `anchorline.despaankamer.nl` from its own repository, deployed by GitHub Actions to the shared Hetzner box, with the Download, Privacy, Terms, Delete-account and Support pages working against a committed fixture that mirrors the published-content contract, plus the `content` publish action in this repository.

**Architecture:** A Next.js App Router site with no database and no state. One module reads a `ContentSource` (the committed fixture on disk, or the public R2 bucket over HTTPS) into an in-memory cache with "keep the last good copy" semantics; pages are server components that render from it, with the committed legal texts as a fallback that is always available. The site ships as a Docker image to GHCR and runs as one container that joins SpaankamerWeb's Caddy network; Caddy proxies by container name. SpaankamerWeb changes are two small PRs that need Egbert's explicit OK.

**Tech Stack:** Next.js 16.4.3, React 19.3.1, Tailwind 4, TypeScript strict, Vitest 4, Playwright, `react-markdown` + `remark-gfm`, `@axe-core/playwright`; Docker on `node:22-bookworm-slim`; GitHub Actions; Dart (`tool/publish/`) for the `content` action.

**Spec:** `docs/superpowers/specs/2026-11-08-website-design.md` (§1, §2, §3, §4.2–4.5, §6, §7 steps 1–2, "Companion work"). The October spec it supersedes and PR #140 define the releases-list contract the fixture copies.

**Scope of this plan:** rollout steps 1 and 2 only. Step 3 (home page, live profile, `tool/site_showcase/`) and step 4 (the manual, `docs/user/`, manual support in the `content` action) get their own plan once the components here exist. Where this plan creates something step 3 or 4 will reuse (the Markdown renderer, the content loader, the header), it says so.

## Global Constraints

- Everything in git is English; commit messages follow Conventional Commits; PR descriptions end with the attribution line; commits carry the `Co-Authored-By` trailer the session gives.
- Nothing is committed, pushed or merged outside the PR flow; every PR waits for Egbert's OK. SpaankamerWeb's deploy workflow, compose file and Caddyfile change only in the PRs named here, each needing his explicit OK before it is opened.
- The builder has no SSH access to the Hetzner box and never asks for it. Server commands are Egbert's, from `deploy/SERVER_SETUP.md`. Verification is through the public address.
- No secret value ever appears in a command's output, a log, a commit or a message. Check a variable with `${VAR:+SET}`, never with `${VAR:-UNSET}`.
- Versions, pinned: `next` 16.4.3, `react` and `react-dom` 19.3.1, `tailwindcss` and `@tailwindcss/postcss` ^4, `typescript` ^5 with `"strict": true`, `vitest` ^4, `@playwright/test` ^1.64, `eslint` ^9 with `eslint-config-next` 16.4.3, Node 22 everywhere (CI, Docker, local). New runtime dependencies beyond this list and `react-markdown`, `remark-gfm`, `@axe-core/playwright` need a one-line reason in the PR.
- Colours, verbatim from spec §3: page background `#0A1419`, card `#142028`, raised `#1F2E38`, orange `#C97B3A` for calls to action and nothing else, text `#E4E9E6`, secondary `#A0AEB6`, muted `#6B7D88`, borders `#3A6477`. Dark only. Inter for text, JetBrains Mono with tabular figures for every number. Flat surfaces, thin borders, no gradients, no illustration.
- No cookies, no analytics, no third-party requests at runtime from the site's pages (fonts are self-hosted by `next/font`; store badge images are committed).
- Markdown renders to plain formatting only; raw HTML and scripts in a text are escaped, never rendered; images load only from the content source or the committed copy.
- Published-content contract (spec §2): `releases/manifest.json` format 1 with `latest`, `previous`, `files.<platform>.{url,size,sha256}`; `content/index.json` format 1 with `texts.<key>.{title,updated,path}`; a reader that meets an unknown `format` treats the file as unavailable; unknown keys are ignored.
- Fixture values are the real 1.1.0 (build 44) files: `Anchorline-1.1.0-windows-x64.exe`, 20098470 bytes, sha256 `4929706574e700339e0636abb6ac5f3226eabfbc6b194119da4ed47427f80262`; `Anchorline-1.1.0-linux-x64.AppImage`, 17623544 bytes, sha256 `51d24b9594ec35be4ab6837ae24030126d63f6a6c23e9e0ccfeee1001d508ea5`; date `2026-11-07`. The placeholder downloads host in the fixture is `https://downloads.invalid` (a reserved name that never resolves).
- Site settings and defaults: `SITE_URL` (default `http://localhost:3000`), `DOWNLOADS_BASE_URL` (unset or empty means fixture mode), `APP_STORE_URL`, `MAC_APP_STORE_URL`, `PLAY_STORE_URL`, `TESTFLIGHT_URL`, `PLAY_TESTING_URL` (empty hides), `SUPPORT_EMAIL` (default `support@anchorline.eu`), and one the plan adds: `SOURCE_REPO_URL` (empty hides the "history" line on legal pages until the repository is public).
- Reduced motion is honoured: no animation beyond focus and hover styles in this plan.
- Settings are read at request time, never baked in: the Docker image is built in CI without the production environment, so every page, layout and metadata route that uses `readSettings()` declares `export const dynamic = "force-dynamic"`. The in-memory cache (Task 10) keeps this cheap.
- Flutter CI in this repository runs `flutter analyze` and `flutter test` over `tool/` and `test/tool/` too; the Dart work must keep both clean. `dart format` is not run over existing files (it churns); new files are formatted.

## Review Focus

Inputs the spec implies but no task's tests would otherwise exercise, most likely to bite first. Each has its test pinned to the owning task below.

1. **An empty releases list** (`latest` null, nothing published yet) must give a download page with the store links and "installers are temporarily unavailable", never a crash or an empty row. Tests: Task 9 (`parseManifest`), Task 13 (page).
2. **A file entry whose `url` is not `https://`** (a typo, or a `pub-*.r2.dev` address that slipped in) must be dropped from the entry while the rest of the list stays usable. Test: Task 9.
3. **A `javascript:` link or an inline `<script>` inside a published text** must come out inert: no `href` with that scheme, the script shown as text. Test: Task 11.
4. **A content-index `path` that climbs out** (`../x`, `/etc/passwd`, `https://evil/x`) must be refused by the source, never fetched. Tests: Task 10 (`FixtureSource`, `HttpSource`), Task 8 (the `/fixtures/` route with `..` and `%2e%2e`).
5. **`DOWNLOADS_BASE_URL` set with a trailing slash or set to an empty string** must behave as one base URL or as fixture mode respectively, never produce `//releases/manifest.json`. Test: Task 3.

---

## File structure

**Site repository** `Egbertdepauw/anchorline-web`, local clone `/Users/egbert/Dev/nextjs/anchorline-web`:

```
.github/workflows/ci.yml            type check, lint, unit tests, build, browser tests
.github/workflows/deploy.yml        build + push image, deploy over SSH
Dockerfile                          3 stages, standalone output, fixtures copied in
docker-compose.prod.yml             one service, no host port, joins spaankamer_external
deploy/env.example                  every setting with its default
deploy/SERVER_SETUP.md              Egbert's one-off commands (server, deploy key, secrets)
scripts/sync-content.sh             copies the legal texts from an app-repo checkout into fixtures/
fixtures/releases/manifest.json     the 1.1.0 fixture list
fixtures/content/index.json         three legal texts
fixtures/content/legal/{privacy,terms,account-deletion}.md
public/brand/                       wordmark-dark.svg, mark-inline.svg, mark-full.svg, icon-512.png, favicon
public/badges/                      app-store.svg, google-play.svg (official artwork)
src/app/layout.tsx                  html/body, fonts, header, footer, metadata
src/app/globals.css                 Tailwind 4 @theme tokens
src/app/page.tsx                    placeholder home (replaced in step 3)
src/app/not-found.tsx, robots.ts, sitemap.ts
src/app/download/page.tsx
src/app/privacy/page.tsx, terms/page.tsx, delete-account/page.tsx
src/app/support/page.tsx
src/app/fixtures/[...path]/route.ts serves fixtures/ read-only
src/components/site-header.tsx, site-footer.tsx
src/components/markdown.tsx         react-markdown with heading ids, safe links and images
src/components/legal-page.tsx       title, last-updated, history line, body
src/components/download-row.tsx     client: per-platform cards, visitor's platform first
src/components/copy-button.tsx      client: copies a sha256
src/components/fixture-notice.tsx
src/lib/settings.ts                 readSettings(env)
src/lib/manifest.ts                 parseManifest, isStaleNightly, entriesNewestFirst
src/lib/content-source.ts           ContentSource, FixtureSource, HttpSource, createContentSource
src/lib/cache.ts                    cached(loader, ttl) with last-good semantics
src/lib/content.ts                  parseContentIndex, parseLastUpdated, splitTitle, createContentLoader
src/lib/site.ts                     the one loader instance built from settings
src/lib/platform.ts                 detectPlatform(userAgent)
src/lib/store-links.ts              storeLink(settings, platform)
src/lib/download-items.ts           buildDownloadItems(settings, manifest)
src/lib/slug.ts                     slugify(text)
src/lib/format.ts                   formatBytes, formatDate
src/content/requirements.ts         system requirements, Windows signing note (site copy)
tests/*.test.ts                     Vitest, node environment
tests/e2e/*.spec.ts                 Playwright, chromium
```

**SpaankamerWeb** (two PRs, each with Egbert's OK): `Caddyfile`, `.github/workflows/deploy.yml`, `src/app/anchorline/page.tsx`.

**This repository**: `tool/publish/lib/content.dart` (new), `tool/publish/lib/cli.dart` (modify), `test/tool/publish/content_test.dart` (new), `test/tool/publish/cli_test.dart` (modify), `.github/workflows/publish-content.yml` (new).

---

## Task 0: Repository and secrets (Egbert)

Nothing in later tasks pushes anywhere until this exists. The builder prepares the commands; Egbert runs them or says "go" for the first two, which only touch his GitHub account.

**Files:** none in a repository yet.

- [ ] **Step 1: Create the repository**

```bash
gh repo create Egbertdepauw/anchorline-web --private --description "Anchorline website" --disable-wiki
```

Expected: `https://github.com/Egbertdepauw/anchorline-web` exists, empty, private.

- [ ] **Step 2: Create the deploy key on Egbert's Mac** (no passphrase; it is only ever read by GitHub Actions)

```bash
ssh-keygen -t ed25519 -C anchorline-web-deploy -f ~/.ssh/anchorline_web_deploy -N ""
```

- [ ] **Step 3: Authorise the key on the server** (Egbert, over his own SSH session; `USER` and host as he logs in today)

```bash
cat ~/.ssh/anchorline_web_deploy.pub | ssh USER@204.168.245.55 'cat >> ~/.ssh/authorized_keys'
```

- [ ] **Step 4: Set the three repository secrets** (values never printed)

```bash
gh secret set VPS_HOST --repo Egbertdepauw/anchorline-web --body 204.168.245.55
gh secret set VPS_USER --repo Egbertdepauw/anchorline-web --body USER
gh secret set VPS_SSH_KEY --repo Egbertdepauw/anchorline-web < ~/.ssh/anchorline_web_deploy
```

Expected: `gh secret list --repo Egbertdepauw/anchorline-web` names the three.

- [ ] **Step 5: Server folder** (Egbert, on the server)

```bash
sudo mkdir -p /opt/anchorline && sudo chown "$USER" /opt/anchorline
```

These five steps are also the first section of `deploy/SERVER_SETUP.md` (Task 4), so they are not lost.

---

## Task 1: Scaffold with CI

**Files:**
- Create: `package.json`, `tsconfig.json`, `next.config.ts`, `postcss.config.mjs`, `eslint.config.mjs`, `vitest.config.ts`, `playwright.config.ts`, `.gitignore`, `.nvmrc` (`22`), `README.md`
- Create: `.github/workflows/ci.yml`
- Create: `tests/smoke.test.ts`, `tests/e2e/smoke.spec.ts`

**Interfaces:**
- Produces: `npm run check` (tsc + lint + unit tests), `npm test`, `npm run test:e2e`, `npm run build`, `npm start`. The `@/` alias to `src/`.

- [ ] **Step 1: Scaffold in the agreed folder**

```bash
cd /Users/egbert/Dev/nextjs && npx create-next-app@16.4.3 anchorline-web --ts --tailwind --eslint --app --src-dir --import-alias "@/*" --use-npm --no-turbopack
```

Then pin `next` to `16.4.3` and `react`/`react-dom` to `19.3.1` in `package.json` and add dev dependencies `vitest@^4`, `@vitejs/plugin-react`, `@playwright/test@^1.64`, `@axe-core/playwright`. Set `output: "standalone"` in `next.config.ts`. Mirror SpaankamerWeb's `eslint.config.mjs` (next core-web-vitals + typescript, same ignores), `vitest.config.ts` (node environment, `tests/**/*.test.ts`, `@` alias) and `playwright.config.ts` (testDir `tests/e2e`, chromium only, `baseURL` from `E2E_BASE_URL` or `http://localhost:3000`, `webServer` runs `npm run dev` locally and `npm start` when `CI` is set, since CI builds first).

- [ ] **Step 2: Scripts**

In `package.json`: `"check": "tsc --noEmit && eslint . && vitest run"`, `"test": "vitest run"`, `"test:e2e": "playwright test"`, plus the generated `dev`, `build`, `start`, `lint`.

- [ ] **Step 3: Smoke tests**

`tests/smoke.test.ts`: one test that `1 + 1 === 2` (replaced in Task 3). `tests/e2e/smoke.spec.ts`: `GET /` responds 200 and the page has a `<main>`.

- [ ] **Step 4: Run everything once**

Run: `npm run check && npm run build && npx playwright install --with-deps chromium && npm run test:e2e`
Expected: all green.

- [ ] **Step 5: CI workflow**

`.github/workflows/ci.yml`, on `pull_request` to `main` and `push` to `main`: `actions/checkout@v7`, `actions/setup-node@v7` with `node-version: 22` and `cache: npm`, `npm ci`, `npx tsc --noEmit`, `npm run lint`, `npm test`, `npm run build`, `npx playwright install --with-deps chromium`, `npm run test:e2e` with `CI=true`.

- [ ] **Step 6: README**

Sections: what the site is (one paragraph, link to the spec by path in the app repository), settings table (the Global Constraints list), fixture mode and how to switch to the bucket, how to run tests, how to deploy (push to main), where the server checklist is.

- [ ] **Step 7: First commit and push**

```bash
git init -b main && git add -A && git commit -m "chore: scaffold the Anchorline site with CI" && git remote add origin git@github.com:Egbertdepauw/anchorline-web.git && git push -u origin main
```

Expected: the CI run on GitHub is green.

---

## Task 2: Brand shell, header, footer, placeholder pages

**Files:**
- Create: `src/app/globals.css`, `src/app/layout.tsx`, `src/app/page.tsx`, `src/app/not-found.tsx`, `src/app/robots.ts`, `src/app/sitemap.ts`
- Create: `src/components/site-header.tsx`, `src/components/site-footer.tsx`
- Create: `public/brand/wordmark-dark.svg`, `public/brand/mark-inline.svg`, `public/brand/mark-full.svg`, `public/brand/icon-512.png`, `src/app/icon.svg` (the inline mark, as favicon)
- Test: `tests/e2e/shell.spec.ts`

**Interfaces:**
- Consumes: `readSettings()` from Task 3 for `siteUrl` in metadata and sitemap. Task 2 and Task 3 may be built in either order; until Task 3 lands, `layout.tsx` uses the `http://localhost:3000` default inline.
- Produces: `<SiteHeader />` (wordmark linking to `/`, links Download and Support; step 4 adds Manual), `<SiteFooter settings={Settings} />` (Privacy, Terms, Support, Delete your account, "Published by Egbert De Pauw"; step 3 adds Open source and Manual), the Tailwind tokens `bg-hull`, `bg-card`, `bg-raised`, `text-surface`, `text-secondary`, `text-muted`, `border-steel`, `text-reel`/`bg-reel`, `font-sans`, `font-mono`, and the utility class `num` (`font-variant-numeric: tabular-nums`).

- [ ] **Step 1: Copy the brand files from the app repository**

From `assets/brand/`: `anchorline-wordmark-dark.svg` → `public/brand/wordmark-dark.svg`, `anchorline-mark-inline.svg` → `public/brand/mark-inline.svg` and also → `src/app/icon.svg` (Next serves it as the favicon), `anchorline-mark-full.svg` → `public/brand/mark-full.svg`, `icon-512.png` → `public/brand/icon-512.png` (social preview only). The app repository stays the source; note that in `public/brand/README.md` (one line).

- [ ] **Step 2: Theme tokens and fonts**

`globals.css`: `@import "tailwindcss"; @theme { --color-hull: #0A1419; --color-card: #142028; --color-raised: #1F2E38; --color-reel: #C97B3A; --color-surface: #E4E9E6; --color-secondary: #A0AEB6; --color-muted: #6B7D88; --color-steel: #3A6477; --font-sans: var(--font-inter); --font-mono: var(--font-jetbrains); }`, `body { background: var(--color-hull); color: var(--color-surface); }`, `.num { font-variant-numeric: tabular-nums; }`, and `@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }`. In `layout.tsx`, `next/font/google` `Inter` and `JetBrains_Mono` with `variable: "--font-inter"` / `"--font-jetbrains"`, `subsets: ["latin"]`, `display: "swap"`, applied to `<html>`.

- [ ] **Step 3: Layout, header, footer, metadata**

`layout.tsx`: `<html lang="en">`, `metadataBase: new URL(settings.siteUrl)`, title template `"%s · Anchorline"` with default `"Anchorline"`, description "Dive logging built for CCR. Imports your Shearwater over Bluetooth and shows cell health, scrubber time and PPO₂ against setpoint.", `openGraph.images: ["/brand/icon-512.png"]` (step 3 replaces with a proper social image). Body: `<SiteHeader />`, `<main>{children}</main>`, `<SiteFooter />`. Header: wordmark (height 28 px) linking to `/`, nav links `Download`, `Support`, a visible focus ring in `reel`. Footer: the inline mark, the five links and the publisher line, on `card` with a `steel` top border. `layout.tsx`, `robots.ts` and `sitemap.ts` declare `export const dynamic = "force-dynamic"`. Both work at 360 px width without horizontal scroll; one line in the header, wrapping links in the footer.

- [ ] **Step 4: Placeholder home, 404, robots, sitemap**

`page.tsx`: the wordmark, the one-line pitch above, and a `Download` link styled as the orange call to action; a muted line "Full site coming." `not-found.tsx`: "This page does not exist" with a link home. `robots.ts`: allow all, `sitemap: ${siteUrl}/sitemap.xml`. `sitemap.ts`: `/`, `/download`, `/privacy`, `/terms`, `/delete-account`, `/support`.

- [ ] **Step 5: Browser test**

`tests/e2e/shell.spec.ts`: on `/`, the header has links with names `Download` and `Support`; the footer has links `Privacy`, `Terms`, `Support`, `Delete your account`; at viewport 360×780 `document.documentElement.scrollWidth <= 360`; axe (`@axe-core/playwright`) reports no violations with impact `serious` or `critical`.

- [ ] **Step 6: Run, commit**

Run: `npm run check && npm run build && npm run test:e2e`
Expected: green.

```bash
git add -A && git commit -m "feat: brand shell with header, footer and placeholder pages"
```

---

## Task 3: Settings

**Files:**
- Create: `src/lib/settings.ts`
- Test: `tests/settings.test.ts` (replaces `tests/smoke.test.ts`)

**Interfaces:**
- Produces:

```ts
export type Settings = {
  siteUrl: string;                 // no trailing slash
  downloadsBaseUrl: string | null; // no trailing slash; null = fixture mode
  fixtureMode: boolean;            // downloadsBaseUrl === null
  appStoreUrl: string | null;
  macAppStoreUrl: string | null;
  playStoreUrl: string | null;
  testflightUrl: string | null;
  playTestingUrl: string | null;
  supportEmail: string;
  sourceRepoUrl: string | null;
};
export function readSettings(env: Record<string, string | undefined> = process.env): Settings;
```

Rules: a variable that is unset, empty or whitespace is `null` (or the default where one exists); trailing slashes are stripped from every URL; a URL that does not start with `http://` or `https://` throws `Error("SETTING_NAME must be an http(s) URL")`.

- [ ] **Step 1: Write the failing tests**

```ts
test("defaults mean fixture mode", () => {
  const s = readSettings({});
  expect(s.siteUrl).toBe("http://localhost:3000");
  expect(s.downloadsBaseUrl).toBeNull();
  expect(s.fixtureMode).toBe(true);
  expect(s.supportEmail).toBe("support@anchorline.eu");
  expect(s.appStoreUrl).toBeNull();
});
test("a trailing slash is stripped", () => {
  expect(readSettings({ DOWNLOADS_BASE_URL: "https://downloads.anchorline.eu/" }).downloadsBaseUrl)
    .toBe("https://downloads.anchorline.eu");
});
test("an empty DOWNLOADS_BASE_URL is fixture mode", () => {
  expect(readSettings({ DOWNLOADS_BASE_URL: "  " }).fixtureMode).toBe(true);
});
test("a non-URL is refused", () => {
  expect(() => readSettings({ SITE_URL: "anchorline.eu" })).toThrow(/SITE_URL/);
});
```

- [ ] **Step 2: Run to see them fail**

Run: `npx vitest run tests/settings.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `readSettings` in `src/lib/settings.ts`**

- [ ] **Step 4: Run to see them pass**

Run: `npx vitest run tests/settings.test.ts`
Expected: PASS (4).

- [ ] **Step 5: Use it in the shell**

`layout.tsx`, `sitemap.ts`, `robots.ts`, `site-footer.tsx` read `readSettings()` instead of inline defaults. Delete `tests/smoke.test.ts`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: site settings from the environment"
```

---

## Task 4: Docker image, compose file, server checklist

**Files:**
- Create: `Dockerfile`, `.dockerignore`, `docker-compose.prod.yml`, `deploy/env.example`, `deploy/SERVER_SETUP.md`

**Interfaces:**
- Produces: the image listens on port 3000 as user `nextjs`; `docker-compose.prod.yml` defines compose project `anchorline`, service `web`, container `anchorline-web`, reading `/opt/anchorline/.env`.

- [ ] **Step 1: Dockerfile**

Three stages on `node:22-bookworm-slim`, as SpaankamerWeb's but without the canvas and Prisma parts: `deps` (`npm ci`), `builder` (`npm run build` with `NEXT_TELEMETRY_DISABLED=1`), `runner` (non-root user `nextjs`, copies `.next/standalone`, `.next/static`, `public`, and `fixtures/` to `/app/fixtures`, since standalone tracing does not follow a runtime `readFile` of that directory; `ENV PORT=3000 HOSTNAME=0.0.0.0`; `CMD ["node", "server.js"]`). `.dockerignore`: `node_modules`, `.next`, `.git`, `tests`, `playwright-report`.

- [ ] **Step 2: Compose file**

```yaml
name: anchorline
services:
  web:
    image: ghcr.io/egbertdepauw/anchorline-web/web:${IMAGE_TAG:-latest}
    container_name: anchorline-web
    restart: unless-stopped
    env_file: .env
    mem_limit: 512m
    networks: [spaankamer_external]
networks:
  spaankamer_external:
    external: true
```

No `ports:`; Caddy reaches the container by name on the shared network (compose project `spaankamer`, network `external`, hence `spaankamer_external`).

- [ ] **Step 3: Environment example**

`deploy/env.example`: every setting from Global Constraints, one per line, with `SITE_URL=https://anchorline.despaankamer.nl` and the rest empty, a comment per line saying what empty means.

- [ ] **Step 4: Server checklist**

`deploy/SERVER_SETUP.md`: Task 0's five steps verbatim; then "first deploy": copy `deploy/env.example` to `/opt/anchorline/.env` and edit; after the first green deploy run, `docker ps --filter name=anchorline-web` shows the container; then the Caddy PR (Task 6) makes it public. Ends with "how to roll back": `IMAGE_TAG=<sha> docker compose -f docker-compose.prod.yml up -d` in `/opt/anchorline`.

- [ ] **Step 5: Build and run locally**

Run: `docker build -t anchorline-web:local . && docker run --rm -d -p 3100:3000 --name al-test anchorline-web:local && sleep 3 && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3100/ && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3100/fixtures/releases/manifest.json; docker rm -f al-test`
Expected: `200` and (after Task 8) `200`; before Task 8 the second is `404`, which is fine.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "build: Docker image, compose file and server checklist"
```

---

## Task 5: Deploy workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

**Interfaces:**
- Consumes: secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` (Task 0); `/opt/anchorline` with a `.env` (Task 0, Task 4).

- [ ] **Step 1: Workflow**

Mirror SpaankamerWeb's `deploy.yml` with one image: name `Deploy`, on `push` to `main` and `workflow_dispatch`; job `build` logs in to `ghcr.io` with `GITHUB_TOKEN`, builds and pushes `ghcr.io/egbertdepauw/anchorline-web/web:latest` and `:${{ github.sha }}` with the GHA cache; job `deploy` (`needs: build`) copies `docker-compose.prod.yml` to `/opt/anchorline` with `appleboy/scp-action@v1.0.0`, then over `appleboy/ssh-action@v1`: `docker login ghcr.io` with `GITHUB_TOKEN` on stdin, `docker pull`, `docker compose -f docker-compose.prod.yml up -d --force-recreate --remove-orphans`, `docker image prune -f`. No `environment:` key; repository secrets.

- [ ] **Step 2: Deploy**

Push to `main` (via PR). Expected: the `Deploy` run is green. Egbert confirms `docker ps --filter name=anchorline-web` shows the container, or the Caddy PR in Task 6 shows it publicly.

- [ ] **Step 3: Commit message**

```bash
git commit -m "ci: deploy the image to the Hetzner box on push to main"
```

---

## Task 6: SpaankamerWeb PR: Caddy block and reload step (Egbert's OK first)

**Files (SpaankamerWeb):**
- Modify: `Caddyfile`
- Modify: `.github/workflows/deploy.yml` (the `Deploy via SSH` script)

- [ ] **Step 1: Ask Egbert's OK** with the exact diff below in the message. Open the PR only after it.

- [ ] **Step 2: Caddy block**

```
anchorline.despaankamer.nl {
    reverse_proxy anchorline-web:3000
}
```

- [ ] **Step 3: Reload step**

In the SSH script, after the `docker compose ... up -d ...` line: `docker compose -f docker-compose.prod.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile`. Caddy resolves `anchorline-web` per request, so the config loads even while that container is absent.

- [ ] **Step 4: Verify after Egbert merges and the deploy runs**

Run: `curl -sI https://anchorline.despaankamer.nl/ | head -5`
Expected: `HTTP/2 200`, a `server: Caddy` header, and the page title in `curl -s https://anchorline.despaankamer.nl/ | grep -o "<title>[^<]*"` is `Anchorline`. `curl -s https://anchorline.despaankamer.nl/robots.txt` contains `Sitemap: https://anchorline.despaankamer.nl/sitemap.xml`, which proves settings are read at request time.

- [ ] **Step 5: Commit message (SpaankamerWeb)**

`feat(caddy): serve anchorline.despaankamer.nl from the anchorline-web container and reload Caddy on deploy`

---

## Task 7: SpaankamerWeb PR: interim page becomes a redirect (Egbert's OK first)

**Files (SpaankamerWeb):**
- Modify: `src/app/anchorline/page.tsx`

- [ ] **Step 1: Ask Egbert's OK.** Open the PR only after Task 6 is live.

- [ ] **Step 2: Redirect**

`page.tsx` becomes a server component that calls `permanentRedirect("https://anchorline.despaankamer.nl/")` from `next/navigation`; remove the `metadata` export. `anchorline-landing.tsx` and `layout.tsx` stay until the domain cutover deletes the folder (spec step 5).

- [ ] **Step 3: Verify**

Run: `curl -sI https://staging.despaankamer.nl/anchorline | head -3`
Expected: `HTTP/2 308` with `location: https://anchorline.despaankamer.nl/`.

- [ ] **Step 4: Commit message (SpaankamerWeb)**

`feat(anchorline): redirect the interim landing page to the Anchorline site`

---

## Task 8: Fixture set and the `/fixtures/` route

**Files:**
- Create: `fixtures/releases/manifest.json`, `fixtures/content/index.json`, `fixtures/content/legal/privacy.md`, `fixtures/content/legal/terms.md`, `fixtures/content/legal/account-deletion.md`
- Create: `scripts/sync-content.sh`
- Create: `src/app/fixtures/[...path]/route.ts`
- Test: `tests/fixtures-route.test.ts`

**Interfaces:**
- Produces: `GET /fixtures/<path>` serves `fixtures/<path>` with `Content-Type` `application/json; charset=utf-8` for `.json`, `text/markdown; charset=utf-8` for `.md`, `application/octet-stream` otherwise, `Cache-Control: no-store`; 404 for a missing file or any segment that is `..`, `.`, empty, or contains `%` after decoding attempts. Exported for the test: `resolveFixturePath(segments: string[], root: string): string | null` in `src/lib/fixture-path.ts`.

- [ ] **Step 1: Sync script**

`scripts/sync-content.sh <path-to-app-repo>`: copies `docs/PRIVACY.md` → `fixtures/content/legal/privacy.md`, `docs/TERMS.md` → `terms.md`, `docs/ACCOUNT_DELETION.md` → `account-deletion.md`; prints `git status --short fixtures/` so a changed `_Last updated_` line is noticed and `index.json` updated by hand. `docs/ACCOUNT_DELETION.md` is in PR #160 of the app repository (branch `claude/agitated-tesla-e5b32e`); until that merges, take the file from that branch with `git show` and re-sync after the merge.

- [ ] **Step 2: Fixture files**

`index.json`: format 1; keys `legal/privacy` (title "Anchorline Privacy Policy", updated `2026-11-08`, path `legal/privacy.md`), `legal/terms` ("Anchorline Terms of Service", `2026-11-08`), `legal/account-deletion` (title from that file's first heading, updated from its `_Last updated_` line). `manifest.json`: format 1; `latest` = version `1.1.0`, build `44`, date `2026-11-07`, the two files from Global Constraints with URLs `https://downloads.invalid/releases/1.1.0/<name>`; `previous: []`; `notes`: Markdown drafted from the pull requests merged since the `v1.1.0` tag (`git log --format=%s v1.1.0..main` in the app repository, 54 commits as of 2026-11-08), two headings "New" and "Fixed", one line per user-visible change, no PR numbers, ending with the line "_Draft; Egbert edits before the first publish._".

- [ ] **Step 3: Failing tests for path resolution**

```ts
test("resolves a plain path under root", () =>
  expect(resolveFixturePath(["releases", "manifest.json"], "/r")).toBe("/r/releases/manifest.json"));
test.each([[".."], ["%2e%2e"], [""], ["."], ["a/b"]])("refuses %s", (seg) =>
  expect(resolveFixturePath(["content", seg, "x.md"], "/r")).toBeNull());
```

- [ ] **Step 4: Run to see them fail; implement `resolveFixturePath` and the route; run to see them pass**

Run: `npx vitest run tests/fixtures-route.test.ts`
Expected: PASS (6). Then `curl -s http://localhost:3000/fixtures/releases/manifest.json | head -3` on `npm run dev` shows the JSON, and `/fixtures/../package.json` is 404.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: committed fixture of the published content and a route that serves it"
```

---

## Task 9: Releases-list reader

**Files:**
- Create: `src/lib/manifest.ts`
- Test: `tests/manifest.test.ts`

**Interfaces:**
- Produces:

```ts
export type FileEntry = { url: string; size: number; sha256: string };
export type ReleaseEntry = { version: string; build: number; date: string; notes: string; files: Record<string, FileEntry> };
export type Manifest = { latest: ReleaseEntry | null; previous: ReleaseEntry[] };
export function parseManifest(text: string): Manifest | null;
export function isStaleNightly(entry: ReleaseEntry, now: Date): boolean;
export function entriesNewestFirst(m: Manifest): ReleaseEntry[];
```

`parseManifest` returns `null` for invalid JSON, a missing or non-1 `format`, or a `latest`/`previous` entry missing `version`, `build`, `date` or `files`; `notes` defaults to `""`; unknown top-level and entry keys are ignored; a file entry whose `url` is not `https://…`, whose `size` is not a positive integer or whose `sha256` is not 64 lowercase hex characters is dropped from `files`. `isStaleNightly` is true when `entry.date` (`YYYY-MM-DD`) is more than 14 days before `now`'s UTC calendar date. `entriesNewestFirst` returns `[latest, ...previous]` in list order without sorting (a roll back makes an older version `latest`).

- [ ] **Step 1: Failing tests**

Fixture strings inline. Cases: the committed fixture parses with `latest.version === "1.1.0"`, `files["windows-x64"].size === 20098470`; `"not json"` → null; `format: 2` → null; `{format:1}` → `{ latest: null, previous: [] }` (review focus 1); an entry with an extra key `"macos-arm64"` under files is kept and `"foo"` at top level ignored; a file with `url: "http://x"` is dropped while its sibling stays (review focus 2); `isStaleNightly({date:"2026-10-20"}, new Date("2026-11-04T00:00:00Z"))` is true and with `"2026-10-21"` false; `entriesNewestFirst` keeps `latest` 1.0.1 ahead of previous 1.1.0.

- [ ] **Step 2: Run to see them fail; implement; run to see them pass**

Run: `npx vitest run tests/manifest.test.ts`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: releases-list reader with the format-1 contract"
```

---

## Task 10: Content source, cache and loader with fallback

**Files:**
- Create: `src/lib/content-source.ts`, `src/lib/cache.ts`, `src/lib/content.ts`, `src/lib/site.ts`
- Test: `tests/content-source.test.ts`, `tests/cache.test.ts`, `tests/content.test.ts`

**Interfaces:**
- Consumes: `Settings` (Task 3), `parseManifest`/`Manifest` (Task 9).
- Produces:

```ts
// content-source.ts
export interface ContentSource { fetchText(path: string): Promise<string | null>; } // null = no such object; throws on failure
export class FixtureSource implements ContentSource { constructor(rootDir: string) }
export class HttpSource implements ContentSource { constructor(baseUrl: string, fetchFn?: typeof fetch) }
export function createContentSource(settings: Settings, fixtureDir?: string): ContentSource;
export function isSafeContentPath(path: string): boolean; // relative, no "..", no leading "/", no scheme, no "%"

// cache.ts
export function cached<T>(loader: () => Promise<T | null>, ttlMs: number, now?: () => number): { get(): Promise<T | null> };

// content.ts
export type TextMeta = { title: string; updated: string; path: string };
export type ContentIndex = { texts: Record<string, TextMeta> };
export function parseContentIndex(text: string): ContentIndex | null;
export function parseLastUpdated(markdown: string): string | null; // "_Last updated: 8 November 2026_" → "2026-11-08"
export function splitTitle(markdown: string): { title: string | null; body: string }; // first "# " heading
export type LegalSlug = "privacy" | "terms" | "account-deletion";
export type LoadedText = { title: string; updated: string | null; markdown: string; fromFallback: boolean };
export interface ContentLoader { manifest(): Promise<Manifest | null>; legal(slug: LegalSlug): Promise<LoadedText>; }
export function createContentLoader(opts: { source: ContentSource; fallbackDir: string; ttlMs?: number; now?: () => number }): ContentLoader;

// site.ts
export const settings: Settings; export const loader: ContentLoader; // built once from readSettings()
```

Semantics. `cached`: within `ttlMs` of the last successful load, return the memo; after that call the loader; a loader that throws or returns `null` leaves the last good value in place and returns it (or `null` when there never was one); the TTL is 5 minutes in `site.ts`. `HttpSource.fetchText` requests `${baseUrl}/${path}` with `cache: "no-store"`, returns `null` on 404, throws on any other non-OK status or network error, and throws before fetching when `isSafeContentPath` is false. `FixtureSource` reads `rootDir/path` and refuses unsafe paths the same way. `legal(slug)` looks up key `legal/${slug}` in the index, fetches `content/${meta.path}`, and on any failure (index unavailable, key missing, fetch failed, unsafe path) returns the committed file `fallbackDir/content/legal/${slug}.md` with `fromFallback: true` and `updated` from `parseLastUpdated`. The title is `meta.title` when published, else the file's first heading; the body never includes the first heading twice (use `splitTitle`).

- [ ] **Step 1: Failing tests**

`cache.test.ts`: first `get()` calls the loader once; a second within TTL does not; after TTL it does; a loader that throws leaves the previous value; a loader returning `null` on the first call yields `null`. `content-source.test.ts`: `isSafeContentPath` accepts `legal/privacy.md`, refuses `../x`, `/x`, `https://evil/x`, `a%2e%2e/x` (review focus 4); `HttpSource` with a fake `fetch` builds `https://dl.example/releases/manifest.json`, maps 404 to `null`, throws on 500; `FixtureSource` reads the committed `fixtures/content/index.json`. `content.test.ts`: `parseLastUpdated("…\n_Last updated: 8 November 2026_\n")` is `"2026-11-08"` and `null` when absent; `splitTitle` on the fixture privacy text gives title `Anchorline Privacy Policy`; `parseContentIndex` with `format: 2` is `null`; `legal("privacy")` with a source that throws returns `fromFallback: true`, `updated: "2026-11-08"` and a body starting with the policy's first paragraph; with the fixture source returns `fromFallback: false`.

- [ ] **Step 2: Run to see them fail; implement; run to see them pass**

Run: `npx vitest run tests/cache.test.ts tests/content-source.test.ts tests/content.test.ts`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: content source, five-minute cache and legal texts with a committed fallback"
```

---

## Task 11: Markdown renderer

**Files:**
- Create: `src/components/markdown.tsx`, `src/lib/slug.ts`
- Test: `tests/markdown.test.tsx` (Vitest with `environment: "node"`, rendering through `react-dom/server`'s `renderToStaticMarkup`)

**Interfaces:**
- Produces: `slugify(text: string): string` (lowercase, letters and digits kept, everything else collapsed to single `-`, trimmed; "Deleting your account" → `deleting-your-account`; a duplicate heading in one document gets `-2`, `-3`). `<Markdown markdown={string} allowedImageOrigins={string[]} />`: `react-markdown` with `remark-gfm`; `h1`–`h4` get `id={slugify(text)}`; `a` with an external `href` gets `rel="noopener noreferrer"`; `img` renders only when its `src` is a relative path or its origin is in `allowedImageOrigins`, otherwise renders `<span>{alt}</span>`; raw HTML is left to react-markdown's default (shown as text); tables, block quotes, lists, emphasis and code spans render. Step 4 (the manual) reuses this component unchanged.

- [ ] **Step 1: Failing tests**

Headings get ids (`## Deleting your account` → `id="deleting-your-account"`); `[x](javascript:alert(1))` renders no `href="javascript:` (review focus 3); `<script>alert(1)</script>` renders as text containing `&lt;script&gt;` and the output has no `<script` (review focus 3); a GFM table renders a `<table>`; `![alt](https://evil/x.png)` with no allowed origins renders `<span>alt</span>` and no `<img`; `![alt](images/a.png)` renders `<img`.

- [ ] **Step 2: Run to see them fail; install `react-markdown` and `remark-gfm`; implement; run to see them pass**

Run: `npm i react-markdown remark-gfm && npx vitest run tests/markdown.test.tsx`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: Markdown renderer with heading anchors and safe links and images"
```

---

## Task 12: Legal pages

**Files:**
- Create: `src/components/legal-page.tsx`, `src/lib/format.ts`, `src/app/privacy/page.tsx`, `src/app/terms/page.tsx`, `src/app/delete-account/page.tsx`
- Test: `tests/format.test.ts`, `tests/e2e/legal.spec.ts`

**Interfaces:**
- Consumes: `loader.legal(slug)` (Task 10), `<Markdown>` (Task 11), `settings.sourceRepoUrl`.
- Produces: `formatDate(iso: string): string` ("2026-11-08" → "8 November 2026"), `formatBytes(n: number): string` (binary units, 1 MB = 1 048 576 bytes; one decimal; MB from 1 MB up, kB below: 20098470 → "19.2 MB"). `<LegalPage slug title updated fromFallback sourceFile markdown />`: `<h1>`, "Last updated 8 November 2026", when `sourceRepoUrl` is set a line "History: this text's changes are in the Anchorline repository" linking to `${sourceRepoUrl}/commits/main/${sourceFile}`, then the body. Each page exports `metadata` with its title and `dynamic = "force-dynamic"`. `delete-account` uses `sourceFile` `docs/ACCOUNT_DELETION.md`, `privacy` `docs/PRIVACY.md`, `terms` `docs/TERMS.md`.

- [ ] **Step 1: Failing unit tests for `format.ts`**

`formatDate("2026-11-08") === "8 November 2026"`; `formatBytes(20098470) === "19.2 MB"`; `formatBytes(17623544) === "16.8 MB"`; `formatBytes(900) === "0.9 kB"`.

- [ ] **Step 2: Run, implement, run**

Run: `npx vitest run tests/format.test.ts`
Expected: PASS.

- [ ] **Step 3: Pages**

Three thin server components calling `loader.legal(...)` and rendering `<LegalPage>`.

- [ ] **Step 4: Browser test**

`tests/e2e/legal.spec.ts`: `/privacy` has an `h1` "Anchorline Privacy Policy", text "Last updated 8 November 2026", and an element with id `deleting-your-account`; `/privacy#deleting-your-account` scrolls that heading into the viewport; `/terms` has an `h1` containing "Terms"; `/delete-account` contains `support@anchorline.eu` and "Delete my Anchorline account"; none of the three has a `<script>` inside `<main>`; axe reports no serious or critical violations on `/privacy`.

- [ ] **Step 5: Run, commit**

Run: `npm run check && npm run build && npm run test:e2e`

```bash
git add -A && git commit -m "feat: privacy, terms and delete-account pages from published content"
```

---

## Task 13: Download page

**Files:**
- Create: `src/lib/platform.ts`, `src/lib/store-links.ts`, `src/lib/download-items.ts`, `src/content/requirements.ts`, `src/components/download-row.tsx`, `src/components/copy-button.tsx`, `src/components/fixture-notice.tsx`, `src/app/download/page.tsx`, `public/badges/app-store.svg`, `public/badges/google-play.svg`
- Test: `tests/platform.test.ts`, `tests/store-links.test.ts`, `tests/download-items.test.ts`, `tests/e2e/download.spec.ts`

**Interfaces:**
- Consumes: `loader.manifest()`, `settings`, `entriesNewestFirst`, `<Markdown>`, `formatBytes`, `formatDate`.
- Produces:

```ts
export type Platform = "ios" | "macos" | "android" | "windows" | "linux" | "unknown";
export function detectPlatform(userAgent: string): Platform; // order: iPhone|iPad|iPod → ios; Android → android; Windows → windows; Macintosh|Mac OS X → macos; Linux|X11 → linux; else unknown
export type StoreLink = { kind: "store" | "beta"; url: string } | { kind: "coming" };
export function storeLink(settings: Settings, platform: "ios" | "macos" | "android"): StoreLink; // store URL, else beta link (TESTFLIGHT_URL for ios and macos, PLAY_TESTING_URL for android), else coming
export type DownloadItem =
  | { platform: Platform; label: string; kind: "file"; url: string; detail: string }   // detail: "1.1.0 · 19.2 MB"
  | { platform: Platform; label: string; kind: "store" | "beta"; url: string }
  | { platform: Platform; label: string; kind: "coming" | "unavailable" };
export function buildDownloadItems(settings: Settings, manifest: Manifest | null): DownloadItem[]; // always five items in order ios, macos, android, windows, linux
```

`<DownloadRow items />` is a client component: it renders the five cards in the given order; after mount it detects the platform from `navigator.userAgent` and gives that card `style={{ order: -1 }}` and the orange call-to-action style (`data-primary="true"`); the row is `display: flex; flex-wrap: wrap` with equal-height cards, so the reorder changes no height. `<CopyButton value />` copies to the clipboard and shows "Copied" for two seconds; renders nothing when `navigator.clipboard` is absent. `<FixtureNotice />` is the muted line "Test build list: these installer links are placeholders until the first release is published."

The page: `<h1>Download Anchorline</h1>`; the row; "Windows and Linux" with `latest`'s version, `formatDate(date)`, notes through `<Markdown>`, and per file its name (last URL segment), `formatBytes(size)` and the sha256 in `font-mono num` with a `<CopyButton>`; under the Windows file the signing note from `requirements.ts`; "Previous versions" as a `<details>` listing `previous` with the same fields; "System requirements" as a table from `requirements.ts` (iOS 15; macOS 12, Subsurface Cloud sync needs macOS 26 on Apple Silicon; Android 7; Windows 10 or 11 on x64; Linux x64 with glibc 2.35 or newer, Ubuntu 22.04 and later); when `manifest` is `null` or `latest` is `null`, the row shows `unavailable` for windows and linux and the section says "The installers are temporarily unavailable. The store links above still work." (review focus 1); `<FixtureNotice>` when `settings.fixtureMode`. Store badges: the official "Download on the App Store" and "Get it on Google Play" artwork, downloaded from Apple's and Google's badge pages into `public/badges/` with a `README.md` naming the source and the guideline page; for `beta` the badge is replaced by a bordered button "Join the beta"; for `coming` by the muted text "Coming to the App Store" / "Coming to Google Play".

- [ ] **Step 1: Failing unit tests**

`platform.test.ts`: iPhone Safari UA → `ios`; iPad with "Macintosh" (iPadOS desktop UA) → `macos` (documented behaviour); Pixel Chrome → `android`; Windows 11 Edge → `windows`; macOS Chrome → `macos`; Ubuntu Firefox → `linux`; `""` → `unknown`. `store-links.test.ts`: with `APP_STORE_URL` set → store; with only `TESTFLIGHT_URL` → beta for ios and macos; with nothing → coming; android follows `PLAY_STORE_URL` then `PLAY_TESTING_URL`. `download-items.test.ts`: with the fixture manifest and empty settings, items are `[coming ios, coming macos, coming android, file windows "1.1.0 · 19.2 MB", file linux "1.1.0 · 16.8 MB"]`; with `manifest: null` windows and linux are `unavailable`.

- [ ] **Step 2: Run, implement, run**

Run: `npx vitest run tests/platform.test.ts tests/store-links.test.ts tests/download-items.test.ts`
Expected: PASS.

- [ ] **Step 3: Components and page, as the Interfaces block above specifies; `download/page.tsx` declares `dynamic = "force-dynamic"`**

- [ ] **Step 4: Browser test**

`tests/e2e/download.spec.ts`: with a Windows UA (`test.use({ userAgent })`), the first card with `data-primary="true"` is the Windows one and its link ends in `Anchorline-1.1.0-windows-x64.exe`; with an Ubuntu UA the AppImage; with an iPhone UA the iOS card and, with no store settings, the text "Coming to the App Store"; the page shows `4929706574e700339e0636abb6ac5f3226eabfbc6b194119da4ed47427f80262`; "Test build list" is visible in fixture mode; axe reports no serious or critical violations; a crawl from `/` over every same-origin `a[href]` (recursive, deduplicated) gets status < 400 for each, with `downloads.invalid` links skipped and every external `href` required to start with `https://`.

- [ ] **Step 5: Run, commit**

Run: `npm run check && npm run build && npm run test:e2e`

```bash
git add -A && git commit -m "feat: download page with store links, installers and checksums from the releases list"
```

---

## Task 14: Support page and release

**Files:**
- Create: `src/app/support/page.tsx`
- Modify: `README.md` (status section)

- [ ] **Step 1: Support page**

`<h1>Support</h1>`; the address as `mailto:` from `settings.supportEmail`; "When you report a problem, include:" with a list: the platform and the app version and build (Settings → About), the dive computer model and firmware, what you did and what happened, screenshots if you have them; a line that the issue tracker link appears when the repository is public (rendered only when `settings.sourceRepoUrl` is set: "Report a bug" → `${sourceRepoUrl}/issues`). The pointer to the manual is added in step 4's plan.

- [ ] **Step 2: Browser test addition**

In `tests/e2e/legal.spec.ts` (rename to `pages.spec.ts`): `/support` contains a `mailto:support@anchorline.eu` link.

- [ ] **Step 3: Lighthouse, by hand**

Run Lighthouse (Chrome DevTools, mobile profile) on `/download` and `/privacy` of the deployed site. Expected: performance and accessibility ≥ 90; note the numbers in the PR.

- [ ] **Step 4: Run, commit, PR, deploy**

Run: `npm run check && npm run build && npm run test:e2e`

```bash
git add -A && git commit -m "feat: support page"
```

Open the PR for the step-2 branch; after Egbert's squash-merge the deploy runs. Verify: `curl -s https://anchorline.despaankamer.nl/download | grep -c 4929706574e7` prints `1`; `/privacy`, `/terms`, `/delete-account`, `/support` return 200.

---

## Task 15: `content` publish action and its workflow (this repository, after PR #140 merges)

**Files:**
- Create: `tool/publish/lib/content.dart`
- Modify: `tool/publish/lib/cli.dart` (the `_Action` enum, `_Options.parse`, `_readEnvironment`, `publishUsage`, the switch in `runPublishCli`)
- Create: `test/tool/publish/content_test.dart`
- Modify: `test/tool/publish/cli_test.dart` (two cases)
- Create: `.github/workflows/publish-content.yml`

**Interfaces:**
- Consumes: `Bucket` (`getText`, `putFile`, `putText(key, text, {contentType, cacheControl})`), `PublishError`, `FakeBucket` (records `textPuts` and `filePuts`), `runPublishCli(args, environment:, bucketFactory:, now:, out:, err:)`, all from PR #140 as merged.
- Produces:

```dart
/// A text published to content/. [key] is its index key, [source] the repository path, [bucketKey] where it lands.
class ContentText { const ContentText({required this.key, required this.source, required this.bucketKey}); }
const List<ContentText> legalTexts = [
  ContentText(key: 'legal/privacy', source: 'docs/PRIVACY.md', bucketKey: 'content/legal/privacy.md'),
  ContentText(key: 'legal/terms', source: 'docs/TERMS.md', bucketKey: 'content/legal/terms.md'),
  ContentText(key: 'legal/account-deletion', source: 'docs/ACCOUNT_DELETION.md', bucketKey: 'content/legal/account-deletion.md'),
];
class ContentIndexEntry { const ContentIndexEntry({required this.title, required this.updated, required this.path}); }
/// "_Last updated: 8 November 2026_" → "2026-11-08"; null when there is no such line or the date does not parse.
String? parseLastUpdated(String markdown);
/// The first "# " heading, trimmed; null when there is none.
String? firstHeading(String markdown);
/// {"format": 1, "texts": {...}} with keys sorted, 2-space indent, trailing newline.
String encodeContentIndex(Map<String, ContentIndexEntry> entries);
class ContentResult { final String indexJson; final List<String> uploadedKeys; }
class ContentPublisher {
  ContentPublisher(Bucket bucket, {required String repoRoot, bool dryRun = false});
  /// Reads every text, refuses (PublishError naming the file) one that is missing, has no first heading or no parseable
  /// last-updated line; uploads each text with contentType 'text/markdown; charset=utf-8' and cacheControl 'no-cache';
  /// then writes content/index.json ('application/json', 'no-cache') last. In a dry run nothing is written.
  Future<ContentResult> publish({List<ContentText> texts = legalTexts});
}
```

CLI: new action `content` with only `--dry-run`; its environment is the four bucket variables, not `DOWNLOADS_BASE_URL` (index paths are relative); usage text gains the line `content   [--dry-run]` and a sentence "content uploads docs/PRIVACY.md, docs/TERMS.md and docs/ACCOUNT_DELETION.md to content/legal/ and rewrites content/index.json." The summary printed on success lists the keys written, or "would write" in a dry run, followed by the index JSON. Step 4's plan extends `legalTexts` with the manual pages (git commit dates, images, removal of stale objects); keep `ContentPublisher.publish` taking the list so that is additive.

- [ ] **Step 1: Failing tests in `test/tool/publish/content_test.dart`**

Using a temp directory as `repoRoot` with the three files written: `parseLastUpdated` on `'# T\n\n_Last updated: 8 November 2026_\n'` is `'2026-11-08'`, on `'# T\n'` is null, on `'_Last updated: 31 Feb 2026_'` is null; `firstHeading('# Anchorline Privacy Policy\n\ntext')` is `'Anchorline Privacy Policy'`; `encodeContentIndex` output equals the expected JSON string with sorted keys and a trailing newline; `publish()` against a `FakeBucket` records `putText content/legal/privacy.md`, `… terms.md`, `… account-deletion.md`, then `putText content/index.json` as the last call, with the content types above; with `dryRun: true` the bucket records no puts and the result's `indexJson` is the same; a missing `docs/TERMS.md` throws `PublishError` whose message contains `docs/TERMS.md` and nothing is uploaded; a file without the last-updated line throws before any upload.

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/tool/publish/content_test.dart`
Expected: FAIL, `content.dart` not found.

- [ ] **Step 3: Implement `content.dart`**

- [ ] **Step 4: Run to see them pass**

Run: `flutter test test/tool/publish/content_test.dart`
Expected: PASS.

- [ ] **Step 5: CLI cases in `cli_test.dart`**

`content --dry-run` with the fixture env and a `FakeBucket` exits 0, prints "would write content/index.json" and performs no puts; `content --version 1` exits 1 with an `::error::` line saying `--version is not used by content`; `content` with `DOWNLOADS_BASE_URL` absent still exits 0 (not required for this action).

- [ ] **Step 6: Wire the action into `cli.dart`; run the whole publish suite and analyze**

Run: `flutter test test/tool/publish && flutter analyze`
Expected: all PASS, "No issues found!".

- [ ] **Step 7: Workflow**

`.github/workflows/publish-content.yml`: name "Publish content"; on `push` to `main` with `paths: [docs/PRIVACY.md, docs/TERMS.md, docs/ACCOUNT_DELETION.md, docs/user/**, tool/publish/**]` and `workflow_dispatch`; one job, `if: vars.PUBLISH_CONTENT == 'on'`, `ubuntu-latest`; steps: `actions/checkout@v7` with `fetch-depth: 0` (the manual's commit dates, later), `subosito/flutter-action@v2` with `channel: stable` and `flutter-version: 3.44.0` (as `ci.yml`), `flutter pub get`, `dart tool/publish/publish.dart content` with `env` mapping `R2_ACCOUNT_ID`, `R2_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` from the repository secrets of the same names. Until the bucket exists the variable is unset and the job is skipped; Egbert sets `PUBLISH_CONTENT=on` in step 5 of the spec's rollout.

- [ ] **Step 8: Commit, PR**

```bash
git add tool/publish/lib/content.dart tool/publish/lib/cli.dart test/tool/publish/content_test.dart test/tool/publish/cli_test.dart .github/workflows/publish-content.yml
git commit -m "feat(publish): content action for the legal texts and a gated publish-content workflow"
```

Branch from `main` after PR #140 is merged; issue → branch → PR → Egbert's squash-merge.

---

## Order and parallelism

- Task 0 first (Egbert). Tasks 1 → 2 → 3 → 4 → 5 in the site repository, sequential (each builds on the previous files); 2 and 3 may swap.
- Task 6 as soon as Task 5's first deploy is green; Task 7 as soon as Task 6 is live. Both are SpaankamerWeb PRs and wait for Egbert's OK before they are opened.
- Tasks 8 → 9 → 10 → 11 → 12 → 13 → 14 in the site repository on one branch "step 2", opened as one PR; Tasks 9, 10 and 11 have no dependency on each other and can run as parallel subagents once Task 8's fixture exists.
- Task 15 in this repository, any time after PR #140 merges; independent of the site work.
- Done for this plan: `anchorline.despaankamer.nl` serves the shell and the five content pages from the fixture with the fallback texts, CI and deploy are green, the interim page redirects, and the `content` action is merged with its workflow skipped until the bucket exists.
