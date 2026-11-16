# Usage Manual — Memos CLI (Linux)

This manual covers the local Linux `memos` CLI: quick capture, per-note local mirror, sync with Memos API, scripts/units, and maintenance. For product scope and architecture, see [`PRD.md`](PRD.md). For deployment (Vercel + Neon), see [`../README.md`](../README.md).

## 1. Overview

**Goal:** capture notes instantly on Linux, maintain a local Markdown mirror, and sync with a self-hosted Memos instance (Vercel + Neon).

**Current implementation:** unified CLI with **per-note mirror** (one `.md` file per memo), **instant local-first quick-capture**, **list/read/pull/create/edit/delete**, **bidirectional sync** (push dirty + flush create/update/delete + pull), **basic conflict detection & resolution**, and **core metadata sync** (best-effort `visibility/state/pinned`, mirrored `tags`). This covers the core of PRD v0.2 Phases 5–6; Phase 7 hardening is partial (attachments, search, backups, observability, merge UX/incremental sync remain evolving).

**Flow:** create/edit locally in mirror (queued if offline / synced in background for quick-capture) → `memos sync`/`push`/timer flushes & pushes changes → pulls remote changes and reconciles.

| Component | Purpose |
|---|---|
| `memos` | Unified CLI/gateway: new/add, list/read/edit/rm, conflicts/resolve, pull/push/sync/flush, completion |
| `memo-quick` | Compatibility wrapper → `memos add` / `memos sync` |
| `memo-nvim` | Compatibility wrapper → `memos new` (editor) |
| `memo-sync.service` / `.timer` | `systemd --user` worker: periodic `memos sync` (push local + pull) |
| `Makefile` / `scripts/install.sh` | Install, update, uninstall, and code-quality targets |

## 2. Prerequisites

- A running Memos instance (`MEMOS_URL`) with PostgreSQL + S3 storage configured and a user account.
- A **Personal Access Token (PAT)** (`MEMOS_TOKEN`), e.g. from Memos UI (*Settings → Access Tokens*).
- Linux with `systemd --user` session.
- Tools: `bash` (4.0+, Linux target), `curl`, `jq` (required). Optional: `libnotify` (`notify-send`).
- For editor flows: `neovim` (`nvim`, or `$EDITOR_NVIM`).
- Network/API calls use `curl` with default timeouts (`--connect-timeout 10 --max-time 30`), overridable via `MEMOS_CURL_CONNECT_TIMEOUT` / `MEMOS_CURL_MAX_TIME`.

## 3. Installation

```bash
make install   # or: ./scripts/install.sh install
make status
```

Installs to `~/.local/bin/{memos,memo-quick,memo-nvim}` and `~/.config/systemd/user/memo-sync.{service,timer}`, creates `~/notes/memos/{notes,.sync}` and `~/.config/memo-quick/env` from `.env.example` if missing (mode 600). Ensure `~/.local/bin` is in `PATH`.

## 4. Configuration

Edit `~/.config/memo-quick/env` (chmod 600):

```bash
MEMOS_URL=https://your-memos.vercel.app
MEMOS_TOKEN=<personal-access-token>

# Optional
MEMOS_VISIBILITY=PRIVATE   # PRIVATE | PROTECTED | PUBLIC (default: PRIVATE)
# MEMOS_API_PATH=          # API root override (e.g. /api or /api/v1); auto-detected if unset
# MEMOS_NOTES_DIR=$HOME/notes/memos
# MEMOS_QUICK_MODE=local          # local (instant, default) | sync (wait for remote ID)
```

- API routes are auto-detected by trying roots (newer `/api/...`, older `/api/v1/...`). Set `MEMOS_API_PATH` to force a root if needed.

## 5. Commands

```bash
memos                      # Neovim scratchpad → create a new note
memos new [--sync] [text...] # new note (editor if interactive, else quick-create)
memos add [--sync] "text"  # quick-create (instant local-first by default)
memos "text"               # shorthand quick-create (instant local-first)
echo "text" | memos add

memos pull                 # pull remote memos into local mirror
memos list                 # list local mirror
memos list --remote        # list from API
memos read <ref>           # show note (uid, name, filename, or prefix match)
memos edit <ref>           # edit in $EDITOR and push update (or queue)
memos rm <ref>             # delete note locally and remotely (alias: delete)
memos conflicts            # list sync conflicts
memos resolve <ref> --keep-local|--keep-remote
                           # resolve a conflict

memos push                 # push local changes (dirty notes + queue), no pull
memos sync                 # reconcile: push local changes + pull
memos flush                # flush outbound queue only

memos completion <shell>   # bash|zsh|fish
memos help
```

**Dispatch:** known subcommand routes; no args → editor new; unknown first arg → quick-create text (local-first by default). `list/read/edit/rm/conflicts/resolve/pull/push/sync/flush` operate on the mirror/API (see below). Quick-capture accepts `--sync`/`--wait` (or `--local`) and honors `MEMOS_QUICK_MODE=local|sync`.

**Shell completions:**
```bash
source <(memos completion zsh)
source <(memos completion bash)
memos completion fish | source
```

## 6. Local Mirror & Sync Model

### Mirror (per-note files)
- `~/notes/memos/notes/<uid>.md` — one file per memo with YAML frontmatter and content body:
  ```md
  ---
  name: memos/<uid>
  uid: <uid>
  visibility: PRIVATE
  state: NORMAL
  pinned: false
  tags: 
  createTime: 2026-...
  updateTime: 2026-...
  ---

  <content>
  ```
  Frontmatter fields tracked/synced (best-effort): `visibility`, `state` (e.g. NORMAL/ARCHIVED), `pinned`. `tags` are mirrored for reference (typically derived from content by Memos). Editing content and/or these metadata fields in the mirror is detected and pushed on `push`/`sync` (subject to API support).
- `~/notes/memos/.sync/state.json` — sync state / id mapping.
- `~/notes/memos/.queue.jsonl` — outbound operation queue (`create`, `update`, `delete`) for offline/failed pushes.

### Behavior
- **Create (quick-capture):** by default `MEMOS_QUICK_MODE=local` for instant UX — `memos add/"text"` (and `memos new <text>`) saves to a local `local-*` mirror entry, queues a `create` op, returns immediately, and triggers a background flush (with `memo-sync.timer` as fallback). Use `--sync` (or `MEMOS_QUICK_MODE=sync`) to wait for remote creation and get a stable remote ID immediately. On flush/sync success the `local-*` entry is reconciled to the remote ID/metadata. Editor-only `memos`/`memos new` (no text) follows the same mode for saving after edit.
- **Pull:** `memos pull` fetches memos from API and writes/updates mirror files + state (cloud treated as authoritative source for pulled records).
- **List/Read:** `memos list` reads local mirror; `memos read <ref>` resolves by uid/name/filename/prefix from mirror.
- **Edit:** `memos edit <ref>` opens content in `$EDITOR`; on change updates local mirror and attempts API update (`PATCH`), else queues `update` op.
- **Delete:** `memos rm <ref>` (or `delete`) removes the note locally and attempts remote delete (`DELETE`), else queues a `delete` op. `memos pull` detects notes deleted remotely (that were previously synced): removes them locally if clean, but keeps local copy and marks conflict (`remoteDeleted`) if locally modified.
- **Push/Flush/Sync:** `memos push` = detect/push dirty mirror notes (content/metadata) + flush outbound queue (no pull). `memos flush` = flush outbound queue only. `memos sync` = push local changes (`push_dirty_notes` + queue) + `pull`. `memo-sync.timer` runs `memos sync` periodically.
- **Conflicts:** `memos conflicts` lists conflicted notes and saved remote copies (`*.remote-conflict-*`). `memos resolve <ref> --keep-local` keeps local (queues/pushes on next sync; if remote was deleted, recreates/queues recreate as a new remote note/ID) and clears conflict markers; `--keep-remote` restores the saved remote version (or removes local if remote deleted). Basic flow, no automatic merge UI.

### Legacy daily logs
Earlier create-only flow appended to `~/notes/memos/YYYY-MM-DD.md` (`## HH:MM` entries) without recording remote IDs. These **legacy logs are not auto-migrated/mapped** into the per-note mirror (to avoid duplicates/ambiguous matching). Recommended: run `memos pull` to build the canonical mirror from cloud; keep old daily files as archive/reference (move aside if desired) and use `notes/*.md` as the working mirror going forward.

### Limitations (current)
- Conflict handling: concurrent edits keep local and save remote as `notes/<uid>.remote-conflict-<ts>.md`; remote-deleted + locally-modified notes are kept locally and marked. `memos conflicts`/`resolve` provide a basic keep-local/keep-remote flow, but there is no merge UI/automatic reconciliation.
- Sync scope: content plus core metadata (`visibility`, `state`, `pinned`) are synced best-effort (subject to API/updateMask support). `tags` are mirrored (often derived from content by Memos) and not force-written. Attachments and richer metadata are not fully synced.
- Change detection/pull is not incremental (cursor-based); reconciliation of edge cases (rename/move, multi-device races) and update deduplication are evolving.
- Legacy append-only `YYYY-MM-DD.md` logs are not auto-migrated into the per-note mirror.
- API shapes vary by Memos version; auto-detection covers common `/api` vs `/api/v1` layouts but edge cases may require `MEMOS_API_PATH` or `MEMOS_DEBUG=1` diagnostics. Desktop compositor keybinds and mobile/desktop client integrations are manual (PRD Phases 3–4).

## 7. Makefile & Maintenance

| Command | Description |
|---|---|
| `make install` / `./scripts/install.sh install` | Install binaries + units, create dirs/config, enable timer |
| `make update` | Update binaries + units, reload/restart timer |
| `make uninstall` | Remove binaries + units (keeps config and notes data) |
| `make status` | Show installed files and timer status |
| `make lint` / `fmt` / `fmt-check` / `check` / `quality` | Shell quality checks (`bash -n`, `shellcheck`, `shfmt`, `hadolint` if installed) |

Quality with Mason tools: `PATH="$HOME/.local/share/nvim/mason/bin:$PATH" make check`.

## 8. Desktop / Editor Integration (hints)

- **Niri/Hyprland:** bind `Mod+N` → `foot --app-id=quicknote memos` (floating 650×400, centered).
- **Neovim:** visual send as new note `vnoremap <leader>mn :w !memos add<CR>`; browse/edit mirror files in `~/notes/memos/notes/` and use `memos edit <ref>` for tracked push (or edit file then sync workflow as it matures).

## 9. Security

- Keep `MEMOS_TOKEN` secret in `~/.config/memo-quick/env` (chmod 600); never commit. Use scoped PAT and rotate if leaked.

## 10. Troubleshooting

- **Auth/sync issues:** verify `MEMOS_URL`/`MEMOS_TOKEN`, try `memos pull` or `memos sync`, set `MEMOS_API_PATH` if auto-detect mismatches your instance.
- **No notes listed:** run `memos pull` to populate mirror from cloud.
- **Queued ops not flushing:** `memos sync` / `memos flush`, check `journalctl --user -u memo-sync.service`.
- **Missing tools:** install `curl`, `jq`, `nvim` as needed.
