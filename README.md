# Memos — Centralized Notes (Vercel + Neon)

Stateless deployment of Memos as a Vercel Container, with Neon as the only persistent storage. See [`docs/PRD.md`](docs/PRD.md) for the full product/architecture spec.

**Upstream:** [usememos/memos](https://github.com/usememos/memos) ([usememos.com](https://www.usememos.com)) — open-source, self-hosted note-taking service.

## Known clients

Any client compatible with the Memos API can be used against your self-hosted instance. Official access is the web UI (installable as a PWA on desktop/mobile). Some known third-party options:

| Client | Platform | Notes |
|---|---|---|
| [Memos Web / PWA](https://www.usememos.com/docs/getting-started) | Windows, macOS, Linux, mobile (browser) | Official web UI; installable as a PWA for app-like access |
| [Moe Memos](https://memos.moe/) ([iOS](https://apps.apple.com/app/moe-memos/id1636903953), [Android](https://play.google.com/store/apps/details?id=me.mudkip.moememos)) | iOS, iPadOS, Android | Native mobile client |
| [Memento](https://github.com/tlwhittaker/memento) | Terminal (TUI) | Community TUI client |

Native third-party mobile apps exist (e.g. Moe Memos); for Windows/macOS/Linux, most people use the official web UI/PWA rather than a dedicated native desktop binary. More community clients and integrations are listed in the [Memos docs](https://www.usememos.com/docs).

## Architecture

Deployment follows a Vercel Container pattern:

| File | Role |
|---|---|
| `vercel.json` | Declares `services.app` with `runtime: "container"` and `entrypoint: "Dockerfile"`, rewrites all traffic to the app service |
| `Dockerfile` | Builds from `neosmemo/memos:stable`, sets runtime env defaults, exposes port `5230` |
| `.vercelignore` | Excludes docs/local files from upload context |
| `.env.example` | Documents required runtime env vars (set real values in Vercel dashboard, not in repo) |

## Required services (Neon)

1. **Neon PostgreSQL** — 1 project, pooled connection string (`?sslmode=require`).
2. **Neon Object Storage** — 1 S3-compatible bucket + endpoint/region/keys.

## Vercel environment variables

Set in Vercel project settings:

| Variable | Value |
|---|---|
| `MEMOS_DRIVER` | `postgres` |
| `MEMOS_DSN` | Neon pooled connection string |
| `MEMOS_MODE` | `prod` |
| `MEMOS_PORT` | `5230` |
| `PORT` | `5230` |

> `MEMOS_DSN` is secret — never commit it.

## Memos admin configuration (after first deploy)

In Memos UI: **Settings > Storage**

| Field | Value |
|---|---|
| Storage Type | `S3` |
| Endpoint / Region | Neon Object Storage endpoint & region (e.g. `ap-southeast-1`) |
| Bucket / Keys | Bucket name, Access Key ID, Secret Access Key |

Create a **Personal Access Token** (admin) for `memo-quick` (Linux) and Moe Memos (Android).


