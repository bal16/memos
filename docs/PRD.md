# PRD: Centralized Note Management & Cross-Platform Quick-Capture System

Status: Draft v0.1 (core architecture decisions locked, see Section 15) · Codename: `memos`

## 1. Overview

A centralized note-taking system that eliminates note fragmentation across five working environments (Windows 11, CachyOS/Niri, CachyOS/Hyprland, CachyOS/GNOME, Android). All notes converge into a single source of truth based on **Memos** running on **Vercel Container** with **Neon PostgreSQL** and **Neon Object Storage**, while local clients keep daily Markdown archives and an offline queue.

Core principle: *local-first, cloud-persistent*. Every note is written to a local file first (instant, offline-friendly), then synchronized to the cloud by a single `memo-quick` gateway and a background `systemd` worker.

## 2. Problem

Notes are currently scattered across local storage isolated by environment:

| Environment | Note storage |
|---|---|
| Windows 11 | Windows Sticky Notes |
| CachyOS Linux (Niri) | Dank Material Shell (DMS) sidebar notes |
| CachyOS Linux (Hyprland) | Noctalia Shell built-in notes |
| CachyOS Linux (GNOME) | GNOME Shell notes extension |
| Android (Xiaomi) | Xiaomi Notes & Google Keep |

Consequences:

- Notes are hard to find because they are scattered.
- Workflows are inconsistent across devices.
- Dependence on UI components specific to each window manager / desktop environment.

## 3. Goals & Success Metrics

| Goal | Success measure |
|---|---|
| Single source of truth | All notes from all devices are visible in Memos cloud; local `.md` archives remain available |
| Instant capture | From keybind to ready-to-type < 300 ms on Linux (NFR-02) |
| Offline-capable | Notes can be created without internet; automatically sent when back online |
| No vendor lock-in | Local archives are standard `.md` files readable by any text editor |
| Zero cost | Infrastructure uses free tiers (Vercel + Neon); no 24/7 home server |
| Easy integration | Neovim, shell widgets, Android, and Windows only need a single interface (`memo-quick` / Memos API) |

## 4. Users & Scenarios

| User | Need | Scenario |
|---|---|---|
| Single user (system owner) | Capture notes quickly anywhere, anytime | `Mod+N` → floating terminal → write → `:wq` → note saved locally + queued for sync |
| Neovim user | Send a text block without opening another app | Select text in *Visual Mode* → `<leader>mn` → sent |
| Mobile user | Capture from home screen | 4x1 *home screen widget* → Moe Memos → cloud |
| Windows user | Full access & capture | Memos PWA pinned to taskbar |

## 5. Scope

### In Scope (MVP)

- **Cloud:** Neon PostgreSQL database + Neon Object Storage bucket + `neosmemo/memos:stable` on Vercel, with S3 storage configured via the admin UI.
- **Local gateway:** `memo-quick` (stdin/arg → daily `.md` → API/queue) and `memo-nvim` (floating scratchpad).
- **Background sync:** `memo-sync.service` + `memo-sync.timer` (`systemd --user`, every 5 minutes / when online).
- **Linux integration:** `Mod+N` keybind in Niri & Hyprland, floating terminal window rules, Neovim `<leader>mn` mapping.
- **Clients:** Moe Memos (Android) + PWA (Windows 11).
- **Lightweight shell widgets:** DMS/Noctalia (Quickshell/QML) and GNOME (GJS) calling `memo-quick` via stdin.

### Phase 2

- Global search across local `.md` archives (e.g. `fzf`/`ripgrep`).
- Usage statistics & note-taking streaks.
- Multi-user / note sharing support (if needed).
- Automatic backup of the `.md` archive to a private git repo as redundancy.

### Out of Scope

- A physical home server running 24/7.
- A full CMS, comment system, or real-time multi-user collaboration.
- Migration or reimplementation of each DE's native note app (they remain as triggers/UI, not data sources).

## 6. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | **Unified Storage:** all notes from all devices converge into a single source of truth accessible from every device | Must |
| FR-02 | **Quick-Capture:** instant note capture via global keybind, Neovim, shell widgets, and phone home screen widget | Must |
| FR-03 | **Local-First & Offline Resilience:** notes can be created/saved locally as Markdown while offline, with a queue (`.queue.jsonl`) that syncs automatically when online | Must |
| FR-04 | **API / CLI Exposure:** expose REST/gRPC API and a local CLI for integration with scripts, Neovim, and shell extensions | Must |
| FR-05 | **Zero Self-Hosted Hardware Dependency:** sync and backend do not depend on a 24/7 physical home server | Must |
| FR-06 | **Single gateway:** all local clients (Neovim, DMS, Noctalia, GNOME) use `memo-quick`; no duplicated HTTP/token logic | Must |
| FR-07 | **Media & attachments:** images/attachments stored in S3-compatible object storage, not on the container's ephemeral disk | Must |

## 7. Non-Functional Requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | **Cost Efficiency:** open-source + free-tier serverless services | $0 operating cost |
| NFR-02 | **Low Latency Capture:** keybind → ready-to-type on Linux | < 300 ms |
| NFR-03 | **Data Portability:** no vendor lock-in, standard `.md` archives | Archives readable by any text editor |
| NFR-04 | **Decoupled Architecture:** sync logic, API auth, and local storage isolated from UI | UI layer only calls the gateway/API |
| NFR-05 | **Reliability (derived):** local writes must not fail due to slow/cloud cold-start | Instant local write; async send |
| NFR-06 | **Security (derived):** tokens & credentials stored securely on clients | `env` chmod 600; scoped PAT |

## 8. Alternatives Analysis

Criteria: cross-OS support, offline capability, quick-capture ease, no home server.

| Evaluation Criterion | Option A: Obsidian + Git (GitHub Private) | **Option B: Memos (Stateless Cloud) + CLI Adapter** | Option C: Notesnook / Standard Notes | Option D: Syncthing P2P |
| --- | --- | --- | --- | --- |
| Data model | Pure `.md` files in local directory | PostgreSQL DB + Object Storage + local `.md` backup | Encrypted local DB (proprietary schema) | Pure `.md` files in local directory |
| Sync infrastructure | GitHub Private Repo (free) | Vercel Container + Neon DB + Neon Object Storage (free) | Third-party vendor cloud (free) | Direct P2P between devices (no server) |
| Neovim & shell integration | Very high (edit files directly) | Very high (CLI `curl`/API & local files) | Low (no official API/CLI) | Very high (edit files directly) |
| Quick-note speed | Fast (requires commit/push script) | Very fast (lightweight API + background queue) | Medium (must open GUI/Electron app) | Fast (background sync) |
| Offline readiness | Full (Git works locally) | Full (local fallback + CLI queue) | Full (built-in offline-first) | Full (but requires both devices online together) |
| Main drawback | Merge conflicts on same file across Android & Linux | ~1–2 s cold-start when container wakes from idle | Hard to automate via shell scripts/Neovim | Sync delayed if laptop is off when phone captures |

**Decision: Option B.** Combines the strengths of A/D (local `.md` archives) with the strengths of B (stateless cloud + instant capture), without C's weakness (not automatable) and D's weakness (sync depends on device uptime).

## 9. Architecture Decision (ADR)

### 9.1 Selected Architecture

Hybrid *local-first* with **stateless Memos (Vercel + Neon)** and a **Unified CLI Core**:

```text
[Client Layer: Neovim / DMS / Noctalia / GNOME / Moe Memos / Windows PWA]
       │
       ▼ (HTTPS / REST & gRPC API)
[Compute Layer: Vercel Container (neosmemo/memos - Stateless, ~100MB)]
       ├──► [Database Layer: Neon Serverless PostgreSQL] (Text, Tags, Metadata, User)
       └──► [Media Layer: Neon Object Storage (S3-Compatible)] (Images, Attachments)
```

**1. Cloud Persistence & Compute Layer (Vercel + Neon)**

- **Compute:** `neosmemo/memos:stable` as a *stateless* container on Vercel. Single Go binary on Alpine (~30–45 MB *compressed*, ~80–110 MB *uncompressed*, ~30–60 MB RAM at runtime), ~1–2 s cold-start.
- **Database:** Neon Serverless PostgreSQL stores structured notes, tags, metadata, and user credentials.
- **Media Storage:** Neon Object Storage (S3-compatible) stores images & attachments, keeping the Vercel container free of state on local disk (*ephemeral filesystem*).

**2. Core Adapter & Local Storage Layer (Linux)**

- A single `memo-quick` CLI as the *single gateway*.
- Every note is **written first** to a daily file (`~/notes/memos/YYYY-MM-DD.md`) before being sent to the API.
- When the network is unavailable or the container is cold-starting, the JSON payload is stored in a `.queue.jsonl` queue and resent asynchronously in the background.

**3. Presentation / Client Layer (Multi-Environment)**

- **CachyOS (Niri, Hyprland, GNOME):** floating terminal Neovim for full writing + custom widgets (Quickshell/QML on DMS & Noctalia, GJS on GNOME) calling `memo-quick` via `stdin`.
- **Android (Xiaomi):** native **Moe Memos** app (offline *local cache* + *home screen widget*) connected directly to the Memos endpoint on Vercel.
- **Windows 11:** Memos **PWA** installed via browser for full access & quick capture.

### 9.2 Rationale

- **Zero Local Disk Dependency in Cloud:** Vercel containers can scale-to-zero, redeploy, or rotate instantly without risk of losing notes/attachments because all state lives in Neon.
- **Single Vendor Storage:** database and object storage quotas & credentials are managed in one Neon project dashboard.
- **Eliminates Duplicated Logic:** GNOME, DMS, Noctalia, and Neovim do not implement their own HTTP clients or token management; they just call `memo-quick`.
- **Offline Resilience:** users do not feel Vercel cold-start latency because local writes and the queue run instantly in the background.

## 10. System Specification

### 10.1 Cloud & Infrastructure (Vercel & Neon)

**PostgreSQL (Neon DB)**
- 1 active database project with a *pooled connection string*: `postgres://<user>:<pass>@<neon-endpoint>/<dbname>?sslmode=require`.

**Object Storage (Neon Object Storage)**
- 1 S3-compatible *bucket* + *Endpoint URL*, *Region* (`ap-southeast-1` recommended), *Access Key ID*, *Secret Access Key*.

**Memos Server Instance (Vercel Container)**
- Image: `neosmemo/memos:stable` (internal port `5230`).
- Environment variables:

| Variable | Value |
|---|---|
| `MEMOS_DRIVER` | `postgres` |
| `MEMOS_DSN` | `<NEON_POSTGRES_POOLED_CONNECTION_STRING>` |
| `MEMOS_MODE` | `prod` |
| `MEMOS_PORT` | `5230` |

- S3 Storage configuration (via Memos Admin UI → *Settings > Storage*):

| Field | Value |
|---|---|
| Storage Type | `S3` |
| Endpoint & Region | per Neon Object Storage bucket credentials |
| Bucket & Keys | bucket name, *Access Key ID*, *Secret Access Key* from Neon |

- Authentication: 1 *Personal Access Token* (Bearer) from the Memos admin account, used by the Linux CLI (`memo-quick`) and the Android client (Moe Memos).

### 10.2 Local Linux (`memo-quick` Core & Daemon)

**System dependencies:** `bash` (or a standalone compiled Go/Rust binary), `curl`, `jq`, `libnotify` (`notify-send`), `systemd` (user session).

**Directory structure:**

```text
~/.local/bin/
├── memo-quick          # Core CLI adapter (stdin/arg -> local md -> Vercel API/queue)
└── memo-nvim           # Floating Neovim scratchpad wrapper

~/.config/memo-quick/
└── env                 # Stores MEMOS_URL (Vercel domain) and MEMOS_TOKEN (chmod 600)

~/notes/memos/
├── YYYY-MM-DD.md       # Daily local Markdown archive
└── .queue.jsonl        # Offline sync queue (JSON Lines)
```

**Background Sync Worker (`systemd --user`):**
- `memo-sync.service` + `memo-sync.timer` run every 5 minutes (or triggered when internet becomes available) to flush `.queue.jsonl` to the Vercel endpoint without user interaction.

### 10.3 Client Interfaces per Environment

1. **Compositor Keybinds (Niri & Hyprland):** global shortcut (`Mod+N`) launches a lightweight terminal (`foot --app-id=quicknote`) running `memo-nvim` in floating mode (650x400, centered). Neovim opens directly in *Insert Mode* with `filetype=markdown`; `:wq` automatically pipes the buffer content to `memo-quick`.
2. **Neovim Internal Integration:** *Visual Mode* mapping (`<leader>mn`) sends the selected text block via `:w !memo-quick`.
3. **Shell Widgets (DMS, Noctalia, GNOME Shell):** a *TextArea* input component executes `memo-quick` as a *child process* and streams text to `stdin`.
4. **Mobile & Windows Clients:** Moe Memos (APK/F-Droid) configured with Vercel *server URL* + *Access Token* + a 4x1 home screen widget; Windows 11 installs the Memos PWA from the Vercel URL and pins it to the *Taskbar*.

## 11. Implementation Milestones

| Phase | Outcome |
|---|---|
| 0. Validation | Confirm Vercel Container support & Neon free tier; test Memos API ↔ Moe Memos |
| 1. Neon & Vercel Setup | Create PostgreSQL database + Object Storage bucket on Neon; deploy `neosmemo/memos:stable`; configure S3 in admin UI |
| 2. Core CLI & Systemd | Create `memo-quick`, `memo-nvim`, and `systemd --user` timer for background queue flush |
| 3. Desktop & Compositor | Add window rules + keybinds in Niri (`config.kdl`) & Hyprland (`hyprland.conf`); Neovim keymap |
| 4. Client & Shell Extensions | Configure Moe Memos (Android), PWA (Windows 11), lightweight UI modules for DMS/Noctalia (Quickshell/QML) & GNOME (GJS) |

## 12. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Vercel 1–2 s cold-start felt during capture | Instant local write + async send; notes are not lost |
| Vercel Container service / free tier changes or becomes unavailable | Stateless architecture makes it easy to move compute (Railway/Fly/Cloud Run) without changing Neon storage; validate in Phase 0 |
| Neon free quota (DB/object storage) exceeded | Monitor usage in Neon dashboard; local `.md` archives remain as backup |
| Moe Memos incompatible with Memos API version | Test connection in Phase 0; prepare an alternative client (direct API) |
| Token leaked from `~/.config/memo-quick/env` | `chmod 600`, scoped PAT, never commit to repo |
| Android captures while laptop is off (not yet synced) | Cloud is the source of truth; Android sends directly to cloud, not to laptop |
| Windows PWA lacks a global keybind | Accept limitation; PWA for access/capture, not a full replacement for Linux keybinds |
| DE-specific shell widgets add complexity | All widgets only wrap `memo-quick` (FR-06); logic stays unified |
| Data conflict if local `.md` and cloud differ | Cloud is the source of truth; local `.md` is an archive/backup, not a competing write target |

## 13. Open Questions

- [ ] Is Vercel Container (including free tier & duration/cold-start limits) available for `neosmemo/memos:stable`?
- [ ] Which Memos API version does Moe Memos support, and is a PAT sufficient for its authentication?
- [ ] Is `neosmemo/memos:stable` the correct/latest image, or should we use `usememos/memos:stable`?
- [ ] Daily file format (`YYYY-MM-DD.md`): one file per day with timestamped entries, or one file per note?
- [ ] Write authority: single user only, or multi-user support needed later?
- [ ] What is the bulk export/backup strategy from cloud to `.md` (bidirectional reconciliation vs one-way)?

## 14. Success Metrics

| Metric | Target |
|---|---|
| Capture latency (keybind → ready-to-type, Linux) | < 300 ms |
| Monthly operating cost | $0 |
| Proportion of notes synced when online | 100% of queue processed during stable connectivity |
| Note-writing availability | 100% (offline writing remains possible) |
| Archive portability | `~/notes/memos/*.md` can be opened/searched without special tools |

## 15. Locked Decisions

| Topic | Decision |
|---|---|
| Architecture option | **Option B**: Stateless Memos (Vercel + Neon) + CLI adapter |
| Source of truth | Cloud (Neon DB); local `.md` is archive & backup |
| Local gateway | Single `memo-quick` (FR-06) |
| Local format | `~/notes/memos/YYYY-MM-DD.md` + `.queue.jsonl` |
| Compute | Vercel Container (`neosmemo/memos:stable`, port 5230) |
| Database & media | Neon PostgreSQL + Neon Object Storage (S3) |
| Android client | Moe Memos |
| Windows client | Memos PWA |
| Cost | $0 (free tiers, no home server) |

## 16. References

- Memos official website: [usememos.com](https://www.usememos.com)
- Official documentation: [usememos.com/docs](https://www.usememos.com/docs)
- GitHub repository: [github.com/usememos/memos](https://github.com/usememos/memos)
