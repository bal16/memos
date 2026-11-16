# Memos — Centralized Notes (Vercel + Neon)

Stateless deployment of Memos as a Vercel Container, with Neon as the only persistent storage. See [`docs/PRD.md`](docs/PRD.md) for the full product/architecture spec.

**Upstream:** [usememos/memos](https://github.com/usememos/memos) ([usememos.com](https://www.usememos.com)) — open-source, self-hosted note-taking service.

## Architecture (reference: `project/satpol`)

Deployment follows the same Vercel Container pattern used in `/home/bal/workspace/project/satpol`:

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

## Local / next steps

- Validate Vercel Container availability & free-tier limits for this image (PRD Fase 0).
- Confirm image tag (`neosmemo/memos:stable` vs `usememos/memos:stable`) and Memos API compatibility with Moe Memos.
- Implement Linux gateway (`memo-quick`, `memo-nvim`, `systemd --user` sync timer) per PRD §10.2.
