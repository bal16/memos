# PRD: Centralized Note Management & Cross-Platform Quick-Capture System

Status: Draft v0.2 (bidirectional sync & editability scope added; core infra decisions retained, sync decisions evolving — see Sections 13 & 15) · Codename: `memos`

## 1. Overview

A centralized note-taking system that eliminates note fragmentation across five working environments (Windows 11, CachyOS/Niri, CachyOS/Hyprland, CachyOS/GNOME, Android). All notes converge into a single system based on **Memos** running on **Vercel Container** with **Neon PostgreSQL** and **Neon Object Storage**.

Core principle (revised): *local-first, cloud-persistent, bidirectionally synchronized*. Notes can be captured, **read, and edited** from Linux locally (Markdown) with low latency and offline resilience, while changes are synchronized in **both directions** with the Memos cloud so local and remote state converge.

> **Implementation note (current state):** Phase 2 (as built) provides local-first **create-only** capture (`memo-quick`/`memo-nvim`) with an outbound queue and no cloud→local pull or edit/update flow. This PRD revision defines the target state (bidirectional sync + edit); see Section 11 milestones.

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

Additional pain (motivating revision): local Markdown archives that do not reflect edits/deletions made in cloud clients (and vice versa) limit usefulness; users need to edit existing notes, not only create new ones.

## 3. Goals & Success Metrics

| Goal | Success measure |
|---|---|
| Single converged system | Notes created/edited on any device converge across Memos cloud and the local Linux mirror |
| Instant capture | From keybind to ready-to-type < 300 ms on Linux (NFR-02) |
| Read & edit locally | Existing notes can be listed/read and edited from local CLI/Neovim workflows and synced to cloud |
| Bidirectional sync | Remote changes (create/edit/delete from web/PWA/mobile) propagate to local `.md`; local changes propagate to cloud |
| Offline-capable | Create/edit locally without internet; queued and reconciled when back online |
| No vendor lock-in | Local representation remains standard `.md` files readable by any text editor |
| Zero cost | Infrastructure uses free tiers (Vercel + Neon); no 24/7 home server |
| Easy integration | Neovim, shell widgets, Android, and Windows use a unified interface/API |

## 4. Users & Scenarios

| User | Need | Scenario |
|---|---|---|
| Single user (system owner) | Capture, read, and edit notes quickly anywhere | `Mod+N` → capture (new note) or open/edit existing → save → local + cloud converge |
| Neovim user | Work in-editor without context switching | Browse/search local mirrored notes in `~/notes/memos`, edit in Neovim, sync updates to Memos; send selection as new note |
| Mobile user | Capture/edit on the go | Moe Memos/PWA create or edit → changes sync back to local Linux mirror |
| Windows user | Full access & capture | Memos PWA pinned to taskbar for read/edit/capture |

## 5. Scope

### In Scope (target / MVP+)

- **Cloud:** Neon PostgreSQL database + Neon Object Storage bucket + `neosmemo/memos:stable` on Vercel, with S3 storage configured via the admin UI.
- **Local gateway & sync:** `memo-quick` (and/or companion tooling) as the *single gateway* for local operations: create, read/list, update/edit, and queue; background sync for **push (local→cloud)** and **pull (cloud→local)** with conflict handling.
- **Local mirror:** `~/notes/memos/` as a bidirectionally synchronized Markdown mirror with stable mapping/metadata to Memos note IDs.
- **Quick capture:** `memo-nvim` (floating scratchpad) and existing keybind/mapping flows for fast new-note capture.
- **Background sync:** `systemd --user` service/timer (and/or on-demand sync) to flush outbound queue and fetch/apply remote changes.
- **Linux integration:** `Mod+N` keybind in Niri & Hyprland, floating terminal window rules, Neovim mappings (send selection as new; open/edit synced notes).
- **Clients:** Moe Memos (Android) + PWA (Windows 11) as first-class remote clients.
- **Lightweight shell widgets:** DMS/Noctalia (Quickshell/QML) and GNOME (GJS) calling the gateway (create, and where feasible list/read).

### Phase 2 / Follow-ups

- Global search across local `.md` mirror (e.g. `fzf`/`ripgrep`) and/or API-backed search.
- Usage statistics & note-taking streaks.
- Multi-user / note sharing support (if needed).
- Automatic backup of the `.md` mirror to a private git repo as redundancy (with care to avoid sync loops).
- Rich attachment/media round-tripping in local mirror.

### Out of Scope

- A physical home server running 24/7.
- A full CMS, comment system, or real-time multi-user collaboration.
- Migration or reimplementation of each DE's native note app (they remain as triggers/UI, not data sources).
- Perfect automatic merge of arbitrary concurrent conflicting edits without a defined resolution policy.

## 6. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | **Unified Storage:** all notes from all devices converge into a single system accessible from every device | Must |
| FR-02 | **Quick-Capture:** instant note creation via global keybind, Neovim, shell widgets, and phone home screen widget | Must |
| FR-03 | **Local-First & Offline Resilience:** notes can be created/edited/saved locally as Markdown while offline, with queued sync when online | Must |
| FR-04 | **API / CLI Exposure:** expose/use REST/gRPC API and a local CLI/gateway for integration with scripts, Neovim, and shell extensions | Must |
| FR-05 | **Zero Self-Hosted Hardware Dependency:** sync and backend do not depend on a 24/7 physical home server | Must |
| FR-06 | **Single gateway:** local Linux clients (Neovim, DMS, Noctalia, GNOME) use the unified gateway; no duplicated HTTP/token logic | Must |
| FR-07 | **Media & attachments:** images/attachments stored in S3-compatible object storage, not on the container's ephemeral disk | Must |
| FR-08 | **Read & list:** list and read existing notes locally (from mirror and/or API) via CLI/editor workflows | Must |
| FR-09 | **Edit & update:** edit existing notes locally and propagate updates to Memos (API update/PATCH) with stable note identity | Must |
| FR-10 | **Bidirectional sync:** pull remote creates/edits/deletes into the local mirror and push local creates/edits/deletes to cloud | Must |
| FR-11 | **Conflict handling:** define and implement a deterministic conflict-resolution policy for concurrent edits (e.g. last-write-wins by timestamp, or keep-both/conflict copy) with user-visible outcomes | Must |
| FR-12 | **Sync state & mapping:** persist mapping between local files/entries and Memos note IDs plus sync metadata (e.g. remote version/update time, local hash) to support idempotent sync | Must |

## 7. Non-Functional Requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | **Cost Efficiency:** open-source + free-tier serverless services | $0 operating cost |
| NFR-02 | **Low Latency Capture:** keybind → ready-to-type on Linux | < 300 ms |
| NFR-03 | **Data Portability:** no vendor lock-in, standard `.md` representation | Notes readable/editable by any text editor |
| NFR-04 | **Decoupled Architecture:** sync logic, API auth, and local storage isolated from UI | UI layer only calls the gateway/API |
| NFR-05 | **Reliability (derived):** local writes must not fail due to slow/cloud cold-start | Instant local write; async send/reconcile |
| NFR-06 | **Security (derived):** tokens & credentials stored securely on clients | `env` chmod 600; scoped PAT |
| NFR-07 | **Consistency (derived):** local mirror and cloud eventually converge after connectivity is restored, per conflict policy | Deterministic, no silent data loss |

## 8. Alternatives Analysis

Criteria: cross-OS support, offline capability, quick-capture ease, no home server, **editability & bidirectional sync**.

| Evaluation Criterion | Option A: Obsidian + Git (GitHub Private) | **Option B: Memos (Stateless Cloud) + CLI Adapter + Sync** | Option C: Notesnook / Standard Notes | Option D: Syncthing P2P |
| --- | --- | --- | --- | --- |
| Data model | Pure `.md` files in local directory | Memos DB + Object Storage + bidirectionally synced local `.md` mirror | Encrypted local DB (proprietary schema) | Pure `.md` files in local directory |
| Sync infrastructure | GitHub Private Repo (free) | Vercel Container + Neon DB + Neon Object Storage (free) | Third-party vendor cloud (free) | Direct P2P between devices (no server) |
| Neovim & shell integration | Very high (edit files directly) | Very high (CLI/API + editable local mirror) | Low (no official API/CLI) | Very high (edit files directly) |
| Quick-note speed | Fast (requires commit/push script) | Very fast (lightweight API + background sync) | Medium (must open GUI/Electron app) | Fast (background sync) |
| Offline readiness | Full (Git local) | Full (local mirror + queued push/pull reconcile) | Full (built-in offline-first) | Full (requires devices online together to exchange) |
| Edit & two-way sync | Native (git merge conflicts possible) | **Target of this revision** (requires custom mapping/conflict policy over Memos API) | Native within app, poor automation | Native file sync, conflict copies possible |
| Main drawback | Merge conflicts; mobile git UX friction | Implementation complexity (ID mapping, conflict resolution, pull+push) and API version variance | Hard to automate via shell scripts/Neovim | Sync delayed if devices not online together |

**Decision: Option B (retained, extended).** Keep Memos stateless cloud + unified gateway, and extend with bidirectional sync/edit so local `.md` becomes a convergent mirror rather than append-only backup.

## 9. Architecture Decision (ADR)

### 9.1 Selected Architecture

Hybrid *local-first* with **stateless Memos (Vercel + Neon)** and a **Unified CLI Core + Sync Engine**:

```text
[Clients: Neovim / DMS / Noctalia / GNOME / Moe Memos / Windows PWA]
       │                              ▲
       │ create/read/edit (API/CLI)   │ remote changes (other clients)
       ▼                              │
[Linux: memo-quick gateway + sync] <──┴── pull/push (HTTPS REST/gRPC)
       │  local mirror ~/notes/memos (Markdown, stable mapping)
       │  sync state/queue (.queue.jsonl, id map/state)
       ▼
[Compute: Vercel Container (neosmemo/memos - Stateless, ~100MB)]
       ├──► [Database: Neon Serverless PostgreSQL] (Text, Tags, Metadata, User)
       └──► [Media: Neon Object Storage (S3-Compatible)] (Images, Attachments)
```

**1. Cloud Persistence & Compute Layer (Vercel + Neon)**

- **Compute:** `neosmemo/memos:stable` as a *stateless* container on Vercel. Single Go binary on Alpine (~30–45 MB *compressed*, ~80–110 MB *uncompressed*, ~30–60 MB RAM at runtime), ~1–2 s cold-start.
- **Database:** Neon Serverless PostgreSQL stores structured notes, tags, metadata, and user credentials (canonical remote records).
- **Media Storage:** Neon Object Storage (S3-compatible) stores images & attachments, keeping the Vercel container free of state on local disk (*ephemeral filesystem*).

**2. Core Adapter, Local Mirror & Sync Layer (Linux)**

- A unified gateway (`memo-quick`, evolvable into subcommands/companion tools) as the *single* local interface for create/read/list/edit and sync.
- **Local mirror:** `~/notes/memos/` contains Markdown representations of notes with **stable mapping** to Memos note IDs and sync metadata (exact format/state files TBD; must support idempotent reconciliation).
- **Push:** local creates/edits/deletes are written locally first, then sent to Memos API (create/PATCH/delete) or queued when offline.
- **Pull:** remote creates/edits/deletes are fetched from Memos API and applied to the local mirror.
- **Conflict policy:** deterministic rule required when local and remote diverge (e.g. compare update timestamps / hashes; resolve via policy such as last-write-wins or keep-both conflict copies) — never silent data loss.
- `systemd --user` worker/timer (and/or on-demand/manual sync) runs reconciliation.

**3. Presentation / Client Layer (Multi-Environment)**

- **CachyOS (Niri, Hyprland, GNOME):** quick-capture via `memo-nvim`/keybinds; browse/edit mirrored notes in Neovim; widgets call the gateway.
- **Android (Xiaomi):** **Moe Memos** (and/or direct API clients) connected to Memos endpoint; changes participate in cloud state and sync to Linux mirror.
- **Windows 11:** Memos **PWA** for access/edit/capture.

### 9.2 Rationale

- **Zero Local Disk Dependency in Cloud:** containers remain stateless; all canonical remote state in Neon.
- **Single Vendor Storage:** database and object storage managed in one Neon project.
- **Unified Logic:** Linux clients go through one gateway/sync layer (no duplicated HTTP/token handling).
- **Offline Resilience & Latency:** local-first writes keep capture/edit responsive; background reconciliation handles cloud cold-starts and connectivity gaps.
- **Convergent Editing:** bidirectional sync + explicit conflict policy enables editing from local and remote clients while preserving portability of `.md` files.

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

- Authentication: 1 *Personal Access Token* (Bearer) from the Memos admin account, used by the Linux CLI/gateway and the Android client (Moe Memos).

### 10.2 Local Linux (Gateway, Mirror & Sync)

**System dependencies:** `bash` (or a standalone compiled Go/Rust binary), `curl`, `jq`, `libnotify` (`notify-send`, optional), `systemd` (user session). Additional tooling may be required for robust sync/state (TBD).

**Directory structure (target, subject to sync design):**

```text
~/.local/bin/
├── memo-quick          # Unified CLI/gateway (create/read/list/edit/sync entrypoints)
└── memo-nvim           # Floating Neovim scratchpad wrapper (quick capture)

~/.config/memo-quick/
└── env                 # Stores MEMOS_URL and MEMOS_TOKEN (chmod 600)

~/notes/memos/
├── YYYY-MM-DD.md       # (Current) daily Markdown capture log / OR per-note files (TBD by mapping design)
├── .queue.jsonl        # Outbound/offline operation queue
└── .sync/              # (Proposed) sync state: id map, remote cursors/timestamps, hashes, conflict artifacts (TBD)
```

**Local format & mapping (to be finalized):** must allow stable association between a local Markdown note/file/section and a Memos note ID, preserve portability, and support detecting local vs remote edits. Options include per-note files with frontmatter/ID, or an indexed daily format — decision pending (see §13).

**Sync Worker (`systemd --user`):**
- Periodic (and/or on-demand) reconciliation: flush outbound queue (push) and pull remote changes (list/get since cursor/update time) into the mirror.
- Applies conflict policy deterministically; records conflicts for user review when needed.

### 10.3 Client Interfaces per Environment

1. **Compositor Keybinds (Niri & Hyprland):** global shortcut (`Mod+N`) launches `foot --app-id=quicknote` running `memo-nvim` in floating mode (650x400, centered) for quick capture (new note). Additional bindings/flows may open browse/edit views over the mirror.
2. **Neovim Integration:** *Visual Mode* mapping (e.g. `<leader>mn`) sends selection as a new note via the gateway; editing files in `~/notes/memos/` (the mirror) should participate in sync (save hook and/or watcher + sync) per final design.
3. **Shell Widgets (DMS, Noctalia, GNOME Shell):** UI components invoke the gateway for create (and, where feasible, list/read) via child process/stdin/stdout.
4. **Mobile & Windows Clients:** Moe Memos (APK/F-Droid) with Vercel *server URL* + *Access Token* + widget; Windows 11 Memos PWA pinned to *Taskbar*. Remote edits flow through cloud and into the Linux mirror via pull sync.

## 11. Implementation Milestones

| Phase | Outcome | Status (as of v0.2 draft) |
|---|---|---|
| 0. Validation | Confirm Vercel Container & Neon free tier; test Memos API ↔ Moe Memos; confirm API version/routes | Partial / in progress (see `docs/research/phase-0-validation.md`) |
| 1. Neon & Vercel Setup | PostgreSQL + Object Storage on Neon; deploy `neosmemo/memos:stable`; configure S3 in admin UI | Done (reported) |
| 2. Core CLI & Systemd (create-only) | `memo-quick` (local-first create + outbound queue), `memo-nvim`, `systemd --user` flush timer, install scripts | Done (baseline) |
| 3. Desktop & Compositor (capture) | Window rules + keybinds in Niri/Hyprland; Neovim send-selection mapping | Pending/manual |
| 4. Client & Shell Extensions | Configure Moe Memos (Android), PWA (Windows 11), lightweight UI modules DMS/Noctalia/GNOME | Pending/manual |
| 5. Read & Local Mirror Foundation | CLI read/list; define stable local format + ID mapping + sync state | Planned |
| 6. Bidirectional Sync & Edit | Push updates/deletes, pull remote changes, edit workflow (CLI/Neovim), conflict policy, reconciliation worker | Planned |
| 7. Hardening | Conflict UX, deletion/attachment handling, search, backups, observability | Planned |

## 12. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Vercel 1–2 s cold-start felt during capture | Instant local write + async send; notes not lost |
| Vercel Container service / free tier changes or unavailable | Stateless architecture enables moving compute (Railway/Fly/Cloud Run) without changing Neon storage; validate in Phase 0 |
| Neon free quota (DB/object storage) exceeded | Monitor usage in Neon dashboard; local mirror remains available |
| Moe Memos incompatible with Memos API version | Test in Phase 0; pin/choose compatible versions or proxy; prepare alternative client |
| Token leaked from `~/.config/memo-quick/env` | `chmod 600`, scoped PAT, never commit to repo |
| **Sync conflicts (concurrent local/remote edits)** | Define deterministic policy (e.g. LWW by update time, or keep-both conflict copies), persist state/IDs, surface conflicts to user; never silently drop content |
| **Data loss on delete or bad merge** | Prefer soft-delete/trash semantics where possible, keep conflict/backups, require explicit destructive sync rules |
| **ID mapping & format drift** (daily log vs per-note files) | Finalize a stable local representation and metadata scheme before full two-way sync; provide migration path from current append-only log |
| **Memos API/version differences** (e.g. `/api/memos` vs `/api/v1/memos`, field shapes) | Abstract API calls, detect/configure endpoint version, test against deployed instance |
| **Complexity increase** (sync engine correctness) | Incremental rollout (read/pull, then edit/push, then deletes/conflicts), idempotent operations, logging/state inspection |
| Android captures while laptop is off | Cloud stores remote state; Android syncs to cloud; Linux mirror reconciles on next pull |
| Windows PWA lacks a global keybind | Accept limitation; PWA for access/capture |
| DE-specific shell widgets add complexity | Widgets only wrap the gateway (FR-06) |

## 13. Open Questions

- [ ] Is Vercel Container (including free tier & duration/cold-start limits) available and sufficient for `neosmemo/memos:stable`?
- [ ] Which Memos API version/routes does the deployed instance expose, and which versions does Moe Memos support (PAT auth)?
- [ ] Is `neosmemo/memos:stable` the correct image/tag, or pin a specific version for client compatibility?
- [ ] **Local mirror format & mapping:** per-note `.md` files (e.g. with frontmatter/ID) vs daily file with addressable entries; how to map to Memos note IDs/names and support edits/deletes?
- [ ] **Conflict-resolution policy:** last-write-wins (by `update_time`), keep-both/conflict copies, or manual merge — and how to surface conflicts?
- [ ] **Sync scope:** include deletions, visibility, tags, pinned/archived state, and attachments in bidirectional sync?
- [ ] **Change detection:** polling (interval/cursor) vs other mechanisms; acceptable sync latency (e.g. timer interval)?
- [ ] **Migration:** how to backfill/map existing cloud notes and existing append-only local `YYYY-MM-DD.md` log into the new synced mirror without duplication?
- [ ] Write authority: single user only, or multi-user support later?

## 14. Success Metrics

| Metric | Target |
|---|---|
| Capture latency (keybind → ready-to-type, Linux) | < 300 ms |
| Monthly operating cost | $0 |
| Sync convergence | Local mirror and cloud converge after connectivity is restored, per conflict policy |
| Outbound queue drain | 100% of queued local operations processed during stable connectivity |
| Note availability | 100% (offline create/edit remains possible) |
| Edit capability | Existing notes can be edited locally and reflected in cloud (and vice versa) |
| Portability | `~/notes/memos` notes remain readable/editable as `.md` without special tools |

## 15. Locked / Evolving Decisions

| Topic | Decision | Status |
|---|---|---|
| Architecture option | **Option B**: Stateless Memos (Vercel + Neon) + unified CLI/gateway | Locked |
| Cloud stack | Vercel Container (`neosmemo/memos:stable`, port 5230), Neon PostgreSQL + Neon Object Storage (S3) | Locked |
| Canonical remote store | **Cloud Memos/Neon** is the canonical remote record; local is a **bidirectionally synced mirror** (replaces "archive/backup only") | **Updated (v0.2)** |
| Local gateway | Single unified gateway (`memo-quick`, extensible) (FR-06) | Locked |
| Sync direction | **Bidirectional** (push local changes, pull remote changes) with conflict policy | **New (v0.2)** |
| Editability | **Create, read, and edit/update** supported (subject to sync design/mapping) | **New (v0.2)** |
| Local format & ID mapping | `~/notes/memos` Markdown mirror with stable mapping/state (exact structure TBD) | **Evolving** (replaces fixed "append-only daily log only") |
| Offline queue | Outbound queue (e.g. `.queue.jsonl`) retained/extended for offline operations | Evolving |
| Clients | Moe Memos (Android), Memos PWA (Windows) | Locked |
| Cost | $0 (free tiers, no home server) | Locked |

## 16. References

- Memos official website: [usememos.com](https://www.usememos.com)
- Official documentation: [usememos.com/docs](https://www.usememos.com/docs)
- GitHub repository: [github.com/usememos/memos](https://github.com/usememos/memos)
- Local project docs: [`MANUAL.md`](MANUAL.md), [`research/phase-0-validation.md`](research/phase-0-validation.md)
