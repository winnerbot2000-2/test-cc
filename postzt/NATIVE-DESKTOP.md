# TryPost Native Desktop (macOS)

A single, double-clickable macOS app that runs the full TryPost stack locally —
no Docker, no database server, no terminal. Built with
[NativePHP Desktop v2](https://nativephp.com/docs/desktop).

The deliverable is `nativephp/electron/dist/TryPost-1.0.8-arm64.dmg`
(ad-hoc signed, Apple Silicon). A `.zip` of the `.app` and an untested
cross-compiled `x64` build sit alongside it.

---

## What changed vs. the Docker stack

| Docker service        | Native equivalent                                                                 |
| --------------------- | --------------------------------------------------------------------------------- |
| `app` (PHP-FPM)       | NativePHP bundles a PHP 8.5 binary and serves Laravel over a pinned loopback port (`http://127.0.0.1:8099`) |
| nginx / Caddy         | Not needed — NativePHP serves the app itself                                       |
| `pgsql`               | SQLite file in the app's data dir (`~/Library/Application Support/trypost/database/database.sqlite`) |
| `redis` (cache/queue) | `database` cache driver + Laravel `database` queue (no Redis)                      |
| queue workers (Horizon)| Four NativePHP queue workers (`default`, `social-publishing`, `ai`, `automations`) — mirrors `config/horizon.php` |
| `reverb`              | `reverb:start` runs as a persistent child process                                  |
| scheduler (`schedule:work`) | NativePHP runs Laravel's scheduler every minute inside the app               |
| Vite dev server       | `npm run build` runs at package time; compiled assets ship in the bundle           |

Key changes to the codebase:

- **`config/nativephp.php`** — app id, window/menu, queue workers, prebuild hooks.
- **`app/Providers/NativeAppServiceProvider.php`** — opens the window, builds the
  menu, starts Reverb, generates Passport keys + personal-access client on first run.
- **`app/Support/NativeSecrets.php` + `native:secrets` command** — store social/AI/Stripe
  credentials in the app's data dir instead of the (readable) bundled `.env`.
- **`config/telescope.php`** — Telescope migration now uses the default connection so
  it lands on the runtime SQLite database.
- **`config/reverb.php` / `config/broadcasting.php`** — deterministic local Reverb secret fallback.
- **`nativephp/electron/`** — published Electron project with two fixes: a *synchronous*
  PHP-binary extraction (the stock async `yauzl` path truncates the binary on Node 24,
  producing a "malformed Mach-O"), and a pinned `127.0.0.1:8099` loopback port so OAuth
  redirect URIs are stable.
- **`scripts/patch-vendor.php`** — idempotent vendor patches (re-applied by a Composer
  `post-autoload-dump` hook so they survive `composer install --no-dev` during packaging):
  Reverb's `StartServer` guards the missing `pcntl` signals, and NativePHP's `FreshCommand`
  signature is fixed for Laravel 13.

---

## Limitations vs. self-hosted TryPost

These are real and worth knowing before relying on the desktop app:

- **OAuth callbacks require a registered loopback redirect URI.** The app is served on
  `http://127.0.0.1:8099`, so each social platform's developer portal must have
  `http://127.0.0.1:8099/accounts/<platform>/callback` listed as a redirect URI
  (and `http://127.0.0.1:8099/auth/<google|github>/callback` for login). Most platforms
  accept loopback URIs (Google and Meta do); a few may not. Platforms that require a
  public HTTPS redirect URI (or inbound webhooks — Telegram, Stripe) still need a tunnel
  (e.g. ngrok) or a companion relay. This is the single biggest "is it *really* fully
  functioning" caveat.
- **Telegram & Discord inbound webhooks** and **Stripe webhooks** need a public URL — out
  of scope for a fully-local app. Set `WEBHOOK_URL` (already supported) to a tunnel if you
  need them.
- **No `pcntl` in the bundled PHP.** Queue workers run fine; Reverb runs (patched to skip
  signal handling); the app is killed by the Electron shell rather than via POSIX signals.
- **No `exif`.** Uploaded photos keep their stored bytes but are not EXIF auto-rotated.
- **`STRIPE`/`CASHIER` billing** is irrelevant — the app runs in `SELF_HOSTED=true` mode
  (no payment gate).
- **No auto-updater** configured (`nativephp.updater.enabled = false`).
- The `.app` is **ad-hoc signed** for local use. Distributing to other Macs requires an
  Apple Developer certificate + notarization, and a re-built PHP binary that passes
  `codesign` (the shipped binary only signs after the synchronous-extraction fix).

---

## Single local account (no login screen)

The desktop build has no login/register screen. On first run it seeds exactly one local
account (`admin@trypost.it` / `password`, via `UserSeeder`), and an
`AutoLoginLocalUser` middleware authenticates that account automatically on every
request — launching the app goes straight to the calendar dashboard.

- The seeded **password is not a real security boundary** in the desktop build: the
  account is auto-authenticated on every launch, so the credential only matters to
  someone who already has physical access to the Mac and its files. It is left in place
  (and the Settings → Authentication "change password" form is kept) so the shared
  Docker/Cloud code path is untouched and login can be re-enabled later without
  reworking the auth system.
- `/login` and `/register` routes still exist (for the shared codebase) but are
  unreachable in the desktop build — the auto-login makes every visitor already
  authenticated, so the `guest` middleware redirects them straight to `/`.

---

## Rebuild from source

Prerequisites: PHP 8.3+, Composer, Node 22+ (the build also needs `unzip`).

```bash
git clone https://github.com/trypostit/trypost.git && cd trypost
cp .env.example .env                       # then set the values documented below
composer install && npm install
php artisan key:generate

# Native setup (downloads Electron + the PHP binary)
composer require nativephp/desktop
script -q /dev/null php artisan native:install --publish   # use `script` for a TTY

# Build the macOS app (ad-hoc signed, local use)
CSC_IDENTITY_AUTO_DISCOVERY=false php artisan native:build mac
# artifacts land in nativephp/electron/dist/
```

The `.env` used for the native build needs (in addition to the normal self-hosted values):

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=http://127.0.0.1:8099
DB_CONNECTION=sqlite
DB_DATABASE=database/database.sqlite
CACHE_STORE=database
QUEUE_CONNECTION=database
BROADCAST_CONNECTION=reverb
REVERB_HOST=127.0.0.1
REVERB_PORT=8080
REVERB_SCHEME=http
REVERB_SERVER_HOST=127.0.0.1
REVERB_SERVER_PORT=8080
SELF_HOSTED=true
```

Set social/AI/Stripe credentials at runtime (not in `.env`) with:

```bash
php artisan native:secrets set OPENAI_API_KEY sk-...
php artisan native:secrets set X_CLIENT_ID   ...
```

> Note: `composer install --no-dev` inside the build re-runs the
> `post-autoload-dump` hook, which re-applies `scripts/patch-vendor.php`. Keep that hook
> in `composer.json` when rebuilding.

### Dev loop

```bash
composer native:dev    # native:run + Vite, concurrently
```
