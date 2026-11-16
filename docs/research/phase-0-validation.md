# Phase 0 Research: Validation

Research date: 2026-11-16  
Scope: PRD Phase 0 and open questions (§11, §13) — Vercel Container viability, Neon tiers, Memos image/tag, Memos API/PAT, and Moe Memos compatibility.  
Methods: Context7 (`/usememos/memos`, `/websites/vercel`, `/websites/neon`) and `google_search`.

> **Note:** Platform pricing/limits and app compatibility change over time. Treat this as a point-in-time snapshot to validate before committing to deployment.

---

## 1. Vercel Container (Compute)

### 1.1 How it works (matches our `satpol` pattern)

- Vercel supports OCI/Docker containers via the **Container runtime** (runs as Vercel Functions / Fluid Compute), built from a root `Dockerfile`/`Containerfile` (or `Dockerfile.vercel`).
- **Multi-service / explicit config:** `vercel.json` can declare services with `runtime: "container"` and `entrypoint: "Dockerfile"` plus `rewrites` to route traffic to a service. Our prepared config mirrors this:

```json
{
  "services": {
    "app": { "root": ".", "entrypoint": "Dockerfile", "runtime": "container" }
  },
  "rewrites": [{ "source": "/(.*)", "destination": { "service": "app" } }]
}
```

- Build/deploy via Vercel CLI or Git; image is built and stored in Vercel's container registry (VCR). Local dev possible with `vercel dev` (requires Docker daemon).
- **Constraints:** containers must serve **HTTP** and listen on `$PORT`; they are **stateless** (no persistent local disk between requests, scale to zero when idle). This is compatible with Memos because state goes to Neon (DB + S3) — but **ephemeral disk means no local SQLite/blob persistence in-container**.

### 1.2 Hobby (free) tier — indicative limits

| Item | Hobby (indicative, verify in dashboard/docs) |
|---|---|
| Use | Personal / non-commercial only |
| Function invocations | ~1,000,000 / month |
| Active CPU | ~4 CPU-hours / month (metered while actively processing) |
| Provisioned memory | ~360 GB-hours / month |
| Fast data transfer | ~100 GB |
| Max duration | Defaults up to ~300 s (5 min) on Hobby |
| Concurrency / scale | Auto-scales (up to large concurrency ceilings reported); Hobby typically runs in a single region (often `iad1`) by default |
| Logs | Limited retention (e.g. ~1 hour runtime logs) |

**Implication:** A low-traffic personal notes backend should fit, but CPU/memory/invocation quotas and duration limits must be monitored. Container image/layer size must stay within platform bundle limits.

### 1.3 Cold starts & always-on behavior

- Idle instances sleep/scale down; new requests after inactivity incur a **cold start** (microVM + container init). Duration depends on image size/runtime/init.
- Lightweight images (Go/Alpine, like Memos) cold-start faster (often a couple of seconds) than heavy images, but **Hobby generally lacks warm/provisioned concurrency**, so cold starts are expected routinely. PRD assumes ~1–2 s; real-world may vary — validate with the actual image.
- **Mitigation (architecture):** local-first capture via `memo-quick` + `.queue.jsonl` means users do not wait on cloud cold-start for capture (PRD §9.2, §12).

### 1.4 Port / runtime fit for Memos

- Memos defaults to port `5230` (`MEMOS_PORT`). Vercel containers must listen on `$PORT` for HTTP. Our `Dockerfile` sets `MEMOS_PORT=5230` and `PORT=5230` and exposes `5230`.
- **Action (validate):** confirm whether Vercel injects/requires a dynamic `$PORT` different from 5230; if so, image/entrypoint or env must bind to `$PORT` (or map accordingly). This is a key Phase 0 deploy check.

### 1.5 Verdict (Vercel)

- **Feasible in principle** for a stateless, low-traffic, personal Memos backend if Hobby container runtime is available on the account and quotas suffice.
- **Risks:** non-commercial clause, cold starts on Hobby, quota ceilings, possible dynamic `$PORT` requirement, and container-runtime feature/tier changes. Validate with a minimal deploy.

---

## 2. Neon (Database & Object Storage)

### 2.1 Neon Serverless Postgres — Free tier (indicative)

| Item | Free tier (indicative) |
|---|---|
| Projects | Up to 100 / account |
| Postgres storage | ~1 GB per project (and account-wide cap reported, e.g. ~20 GB total across projects) |
| Compute | ~100 CU-hours / project / month (enough for a small 0.25 CU instance for many hours/month) |
| Autoscaling | 0 to 2 CU (when active) |
| Scale to zero | After ~5 minutes inactivity (saves compute hours) |
| Branches | ~10 / project |
| Egress (public transfer) | ~5 GB / project / month |
| History / restore | Short window (e.g. ~6 h, capped) |

**Pooled vs direct connection strings (important):**

- **Pooled** (hostname includes `-pooler`): routes through PgBouncer, supports high concurrency (up to ~10,000 client connections multiplexed), **transaction mode** (session state like `LISTEN/NOTIFY`, temp tables, SQL `PREPARE` does not persist across transactions). Use for app/runtime.
  - `postgresql://user:pass@ep-...-pooler.<region>.aws.neon.tech/<db>?sslmode=require`
- **Direct** (no `-pooler`): direct to Postgres, limited by `max_connections`; use for migrations/session-level operations.
  - `postgresql://user:pass@ep-...<region>.aws.neon.tech/<db>?sslmode=require`

**For Memos:** set `MEMOS_DRIVER=postgres` and `MEMOS_DSN` to the **pooled** connection string (PRD/README already specify pooled). Verify Memos/driver behavior with transaction-mode pooling; keep a direct URL handy if migrations/tools need it.

### 2.2 Neon Object Storage (S3-compatible) — Free tier (indicative)

| Item | Indicative value |
|---|---|
| Free allowance | ~5 GB per project |
| S3-compatible | Yes (usable as S3 endpoint for apps) |
| Branching | Buckets/objects branch with the Neon project (relevant if using DB branches) |
| Paid overage (reference) | ~$0.023/GB-month storage; no per-operation charge reported; egress counts toward public network transfer allowance (shared) |

**Implication:** 5 GB/project is sufficient for a personal notes/attachments MVP; monitor usage. Configure in Memos as S3-compatible storage (endpoint, region e.g. `ap-southeast-1`, bucket, access/secret keys).

### 2.3 Verdict (Neon)

- **Good fit** for $0 MVP: free Postgres + 5 GB S3-compatible object storage per project, pooled connections for stateless compute. Validate actual current quotas in Neon dashboard at setup time.

---

## 3. Memos Container Image & Tags

| Topic | Finding |
|---|---|
| Official Docker Hub image | **`neosmemo/memos`** (published under `neosmemo` Docker Hub account; GitHub org is `usememos/memos`) |
| Recommended tag (production) | **`neosmemo/memos:stable`** — tracks latest stable release |
| Pinned stability | Versioned tags (e.g. `neosmemo/memos:<version>` or monthly series) for reproducibility |
| `:latest` | Development-oriented / recent builds; **not recommended for production** |
| `:canary` | Bleeding-edge/nightly; not for production |
| `usememos/memos` on Docker Hub | Not the canonical published image namespace; prefer `neosmemo/memos` to avoid ambiguity |

**Decision impact:** PRD and our `Dockerfile` currently use `neosmemo/memos:stable` — **correct choice** for MVP. For reproducibility, consider pinning a known-good version once validated (and document the pinned tag).

---

## 4. Memos API, Auth (PAT), and Endpoints

### 4.1 Authentication

- Memos supports **Personal Access Tokens (PAT)** for programmatic/API access.
- Tokens are generated in the web UI (user/account settings) and use the `memos_pat_...` prefix.
- Use HTTP header: `Authorization: Bearer memos_pat_<token>`.
- PAT carries the user's permissions; store securely client-side (for us: `~/.config/memo-quick/env`, `chmod 600`, scoped/limited to needed account).

### 4.2 API routes & versioning (important for clients)

Memos has undergone breaking API/routing changes across versions:

| Era (approx.) | Route style (indicative) | Example create-memo endpoint |
|---|---|---|
| Older (e.g. ~0.30–0.31, v1 era) | `/api/v1/...` | `POST /api/v1/memos` |
| Newer (e.g. 26.10+ / post-v1) | flat `/api/...` (and gRPC/Connect procedures moved; old v1 paths may return `410 Gone`) | `POST /api/memos` |

- **Create memo (typical):** `POST <base>/api/memos` (or `/api/v1/memos` on older), JSON body e.g. `{ "content": "...", "visibility": "PRIVATE|PROTECTED|PUBLIC" }` (defaults often PRIVATE). Exact schema/fields can vary by version — confirm against the deployed server's API.
- **`memo-quick` implication:** must target the endpoint style of the deployed Memos version (discoverable from server docs/UI or by probing). Make base path/version configurable.

### 4.3 Storage configuration (S3) — API/env note

- S3 is configured as instance **STORAGE** setting (Admin UI → Settings > Storage) stored in DB by default.
- No direct flat `MEMOS_S3_*` env vars auto-read by Memos; declarative file-backed config (`memos-instance-setting-*.json`, default scanned under `/etc/secrets`) can define STORAGE (and supports `${env:...}` interpolation in declarative configs). For MVP prefer UI config; declarative/env-interpolated config is an advanced/validation option.

---

## 5. Moe Memos (Android) Compatibility

### 5.1 Supported server versions (reported)

Moe Memos tracks specific Memos server releases due to breaking API changes. Reported supported ranges include (verify current README/releases at implementation time):

- **Memos 0.21.0**
- **Memos 0.27.0 – 0.31.0** (v1 `/api/v1` era)
- **Memos 26.10 – 26.11** (post-v1 flat `/api` era)

> Exact supported set changes with Moe Memos app releases; always check the Moe Memos repo/app release notes for the version you install.

### 5.2 Auth & connectivity

- Moe Memos authenticates using a **Personal Access Token (PAT)** (`memos_pat_...`) and server URL; token stored securely on device.
- Connection issues are often **API version mismatch** (client expects different routes/procedures than server exposes), misconfigured HTTPS/reverse proxy, or expired/revoked token.

### 5.3 Handling newer/unsupported server versions

- If the server is newer than Moe Memos supports (e.g. API/routes changed beyond its mappings), a translation proxy such as **Mortis** (`mudkipme/mortis`) can bridge newer Memos API to a format Moe Memos expects. This adds operational complexity (another component) — consider when choosing server version.

### 5.4 Verdict (Moe Memos)

- **PAT-based auth is compatible** with Memos' access token model.
- **Main risk is version skew:** choose/pin a Memos server version that matches the Moe Memos release you plan to use (or budget for Mortis). This directly affects the **image tag/version** decision in §3.

---

## 6. Phase 0 Validation Checklist (actionable)

### Vercel
- [ ] Confirm Container runtime availability on the target Vercel account/plan (Hobby, non-commercial).
- [ ] Deploy minimal `neosmemo/memos:stable` with Neon `MEMOS_DSN`; verify it serves HTTP.
- [ ] Verify `$PORT` behavior (static 5230 vs injected dynamic port) and adjust if needed.
- [ ] Observe cold-start latency and basic CPU/memory/invocation usage.

### Neon
- [ ] Create Neon project: Postgres DB + pooled connection string (`-pooler`, `sslmode=require`) and (if needed) direct URL.
- [ ] Create Neon Object Storage bucket (S3-compatible) and note endpoint/region/keys; confirm free-tier quotas.
- [ ] Confirm Memos works with pooled (transaction-mode) connection.

### Memos image & config
- [ ] Use `neosmemo/memos:stable` for initial test; record exact resolved version, then decide whether to pin a version compatible with Moe Memos.
- [ ] Configure S3 in Admin UI (Settings > Storage) and verify upload/retrieval.
- [ ] Create admin PAT; verify `Authorization: Bearer memos_pat_...` works against the deployed version's memo-create endpoint (`/api/memos` vs `/api/v1/memos`).

### Moe Memos
- [ ] Install target Moe Memos release; check its documented supported Memos server versions.
- [ ] Select/pin Memos server version to match (or plan Mortis proxy). Test login + create/read memo with PAT over HTTPS endpoint.
- [ ] Confirm offline/local-cache behavior meets needs (Android is direct-to-cloud client).

---

## 7. Recommended Decisions (to unblock Phase 1)

1. **Image:** start with `neosmemo/memos:stable` for deploy validation; **pin to a specific version** that is explicitly compatible with the chosen Moe Memos release once confirmed (version alignment is the critical constraint).
2. **DB:** Neon Postgres with **pooled** `MEMOS_DSN` (`sslmode=require`).
3. **Object storage:** Neon S3-compatible bucket, configured via **Memos Admin UI** (MVP); revisit declarative `${env:...}` only if automated provisioning becomes necessary.
4. **Auth:** admin-created **PAT** for `memo-quick` and Moe Memos; store with `chmod 600`, never commit.
5. **Capture UX:** rely on local-first `memo-quick` + queue to mask Vercel cold starts (core architecture assumption).

## 8. Source Pointers

- **Context7:** `/usememos/memos` (deployment/config provisioning, STORAGE instance settings, runtime config loading `/etc/secrets`, API/auth context), `/websites/vercel` (container runtime, services/vercel.json, Dockerfile), `/websites/neon` (plans, pooled/direct connections, object storage).
- **Google Search (topics):** Vercel container runtime/Docker + Hobby limits & cold starts (2026), Vercel `services`/vercel.json container config, Neon Postgres free tier & pooled connection string, Neon Object Storage S3-compatible limits/pricing, `neosmemo/memos` vs `usememos/memos` tags, Memos REST API create memo + Bearer PAT, Moe Memos supported server versions/API v1 vs flat `/api` and Mortis proxy.
- **Primary product refs:** https://www.usememos.com/docs , https://github.com/usememos/memos , https://vercel.com/docs , https://neon.com/docs , Moe Memos repo/releases (check current).
