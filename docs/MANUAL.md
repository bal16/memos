# Usage Manual — Memos CLI (Linux)

This manual covers day-to-day usage of the local Linux quick-capture setup implemented in this repo, the scripts/units it provides, and maintenance (install/update/lint). For product scope and architecture, see [`PRD.md`](PRD.md). For deployment (Vercel + Neon), see [`../README.md`](../README.md).

## 1. Overview

**Goal:** capture notes instantly on Linux, keep a local Markdown archive, and sync to the self-hosted Memos instance (Vercel + Neon) in the background.

**Current implementation (baseline):** local-first **create-only** capture with outbound queue and periodic flush. **Planned (PRD v0.2):** read/list/edit and bidirectional sync (see PRD §11).

**Flow:** `memos`/input → write to local daily file → try Memos API (create) → on failure queue to `.queue.jsonl` → `memo-sync.timer` flushes periodically.

| Component | Purpose |
|---|---|
| `memos` | Unified CLI/gateway (subcommand routing): new (editor), add/quick-create, sync/flush; future list/read/edit/pull/push |
| `memo-quick` | Compatibility wrapper → `memos add` / `memos sync` |
| `memo-nvim` | Compatibility wrapper → `memos new` (editor) |
| `memo-sync.service` / `.timer` | `systemd --user` worker to flush the offline queue every 5 minutes |
| `Makefile` / `scripts/install.sh` | Install, update, uninstall, and code-quality targets |

## 2. Prerequisites

- A running Memos instance (URL) with PostgreSQL + S3 storage configured and a user account.
- A **Personal Access Token (PAT)** for the account (Memos UI: *Settings → My Account/Access Tokens*; token often starts with `memos_pat_`).
- Linux with `systemd --user` session.
- Tools: `bash`, `curl`, `jq` (required for sync/queue). Optional: `libnotify` (`notify-send`) for notifications.
- For scratchpad/keybind: `neovim` (`nvim`), and a terminal such as `foot` (as used in examples).

## 3. Installation (from this repo)

```bash
# from repo root
make install
# or
./scripts/install.sh install
```

`make install` will:
- Install `memos`, `memo-quick`, and `memo-nvim` to `~/.local/bin/`
- Install systemd user units to `~/.config/systemd/user/memo-sync.{service,timer}`
- Create `~/notes/memos/` (local archive + queue)
- Create `~/.config/memo-quick/env` from `.env.example` if missing (mode 600) — **you must edit it**
- Enable & start `memo-sync.timer` (best-effort)

Ensure `~/.local/bin` is in your `PATH`.

Check status:

```bash
make status
# or
./scripts/install.sh status
```

## 4. Configuration

Edit `~/.config/memo-quick/env` (keep it secret, `chmod 600`):

```bash
# Required for sync
MEMOS_URL=https://your-memos.vercel.app
MEMOS_TOKEN=<personal-access-token>

# Optional
MEMOS_VISIBILITY=PRIVATE   # PRIVATE | PROTECTED | PUBLIC (default: PRIVATE)
# MEMOS_API_PATH=/api/memos   # force endpoint; if unset, auto-tries /api/memos then /api/v1/memos
# MEMOS_NOTES_DIR=$HOME/notes/memos
```

- `MEMOS_URL`: base URL of your Memos instance (no trailing slash required).
- `MEMOS_TOKEN`: PAT (treat like a password). Do **not** commit real values; repo `.env.example` is placeholders only.
- `MEMOS_API_PATH`: Memos API routes differ by version (newer: `/api/memos`, older: `/api/v1/memos`). Auto-detection tries both; set explicitly if needed.

Template variables are also documented in the repo’s [`.env.example`](../.env.example).

## 5. Commands & Behavior

### 5.1 `memos` (unified CLI, primary)

**Location (installed):** `~/.local/bin/memos` (source: `linux/bin/memos`)

**Subcommands / routing:**

```bash
memos                      # open Neovim scratchpad → create a new note
memos new                  # new note (editor if interactive; stdin/args → quick-create)
memos new "text"           # quick-create new note
echo "text" | memos new    # quick-create from stdin

memos add "text"           # quick-create new note
memos quick "text"         # alias for quick-create
memos "text"               # shorthand quick-create (unknown non-command arg)

memos sync                 # flush offline queue (.queue.jsonl)
memos flush                # alias for sync
memos help                 # show help (-h/--help)

# Planned (not yet implemented): list, read, edit, pull, push
```

**Dispatch rules:** known subcommand → routed accordingly; `memos` with no args → editor (new); unknown first argument → treated as quick-create text (shorthand).

**Behavior (local-first, create-only):**
1. Reads content from arguments, stdin, or Neovim scratchpad (for `new`/default editor flow).
2. **Always writes locally first** to `~/notes/memos/YYYY-MM-DD.md`, appending a timestamped entry:
   ```markdown

   ## HH:MM

   <content>
   ```
3. Attempts to create the memo via Memos API (`POST <MEMOS_URL><api-path>` with `Authorization: Bearer <token>` and JSON `{"content":"...","visibility":"..."}`).
4. On success: exits 0 (optional desktop notification “Saved & synced”).
5. On failure (network error, cold start, non-2xx, missing config/tools): enqueues a JSON line in `~/notes/memos/.queue.jsonl` and exits 0 (notification “Saved locally (queued for sync)”). Local note is never lost due to sync failure.

**Queue:** `.queue.jsonl` stores one JSON object per line (`content`, `visibility`, `created_at`). `memos sync` retries each entry, removes successes, keeps failures, and reports `ok/failed`.

**Editor flow (`memos` / `memos new` interactive):** opens a temp `.md` in Neovim (`$EDITOR_NVIM` or `nvim`) with `filetype=markdown` in Insert Mode; on exit, non-empty saved content is created as a note.

**Dependencies:** `curl`, `jq` for API/queue; `notify-send` optional; `nvim` for editor flow.

### 5.2 Compatibility wrappers

- **`memo-quick`** (`~/.local/bin/memo-quick`): `memo-quick "text"` / stdin → `memos add ...`; `memo-quick --flush|--sync` → `memos sync`; `--help` → `memos help`.
- **`memo-nvim`** (`~/.local/bin/memo-nvim`): `memo-nvim` → `memos new` (editor).

Wrappers resolve `memos` next to themselves (or from `PATH`/`$MEMOS_BIN`), so installed and in-repo usage both work.

### 5.3 Background sync (`systemd --user`)

**Units (installed):** `~/.config/systemd/user/memo-sync.service`, `~/.config/systemd/user/memo-sync.timer` (source: `linux/systemd/`)

- **Service:** oneshot, runs `%h/.local/bin/memos sync` (waits for `network-online.target`).
- **Timer:** starts 2 minutes after boot, then every 5 minutes (`OnUnitActiveSec=5m`), `Persistent=true`.

**Manage manually:**
```bash
systemctl --user status memo-sync.timer
systemctl --user start memo-sync.service   # flush now
systemctl --user enable --now memo-sync.timer
systemctl --user disable --now memo-sync.timer
journalctl --user -u memo-sync.service -n 50 --no-pager
```

> Note: outbound queue flush only (create). Bidirectional pull/push sync is planned (PRD v0.2).

## 6. Makefile & Maintenance Scripts

Run from repo root:

| Command | Description |
|---|---|
| `make install` / `./scripts/install.sh install` | Install binaries (`memos`, wrappers) + units, create config/notes dirs, enable timer |
| `make update` / `./scripts/install.sh update` | Update binaries + units, `daemon-reload`, restart timer |
| `make uninstall` | Remove binaries + units (keeps `~/.config/memo-quick` and `~/notes/memos`) |
| `make status` | Show installed files, config/notes paths, timer status |
| `make enable-timer` / `make disable-timer` | Enable/start or disable/stop the timer |
| `make lint` | `bash -n` (always), `shellcheck -x` and `hadolint Dockerfile` if installed |
| `make fmt` | `shfmt -w -i 2 -ci -sr` on shell scripts if installed |
| `make fmt-check` | `shfmt -d` (check only) |
| `make check` | `lint` + `fmt-check` |
| `make quality` | Alias for `check` |

**Quality tools:** `shellcheck`, `shfmt`, `hadolint` are optional; targets skip gracefully if missing. If you use LazyVim/Mason-installed tools (not on `PATH`), run for example:
```bash
PATH="$HOME/.local/share/nvim/mason/bin:$PATH" make check
```

## 7. Desktop / Editor Integration (Phase 3 hints)

Not automated by `make install`; configure per environment:

- **Niri / Hyprland:** bind `Mod+N` to launch `foot --app-id=quicknote memos` (or `memo-nvim`) and add a floating window rule (e.g. 650x400, centered).
- **Neovim (visual send as new note):** map selection to pipe into quick-create, e.g. `vnoremap <leader>mn :w !memos add<CR>` (or keep `:w !memo-quick`).
- **Shell widgets (DMS/Noctalia/GNOME):** execute `memos add` (or `memo-quick`) as a child process and stream text to stdin (no duplicated HTTP/token logic, FR-06).

## 8. Data & Paths

| Path | Purpose |
|---|---|
| `~/.config/memo-quick/env` | Client config (`MEMOS_URL`, `MEMOS_TOKEN`, options), chmod 600 |
| `~/notes/memos/YYYY-MM-DD.md` | Local daily Markdown capture log (append-only, timestamped entries) |
| `~/notes/memos/.queue.jsonl` | Offline outbound queue (JSON Lines) |
| `~/.local/bin/memos`, `~/.local/bin/memo-quick`, `~/.local/bin/memo-nvim` | Installed CLI and compatibility wrappers |
| `~/.config/systemd/user/memo-sync.{service,timer}` | Installed user units |

**Important (current behavior):** local `.md` is an append-only capture log/archive — **not bidirectionally synced**. Each create produces a new local entry and a new cloud memo (no edit/update by ID, no cloud→local pull). Edits/deletes in Memos cloud do not reflect locally; editing local `.md` does not update cloud. Cloud (Memos/Neon) remains the canonical remote store (PRD v0.2). Read/edit and bidirectional sync are planned.

## 9. Troubleshooting

- **“Saved locally (queued for sync)” / notes not appearing online:** check `MEMOS_URL`/`MEMOS_TOKEN` in `~/.config/memo-quick/env`, token validity/scopes, and that the instance is reachable. Try `memos sync` and inspect with a manual `curl` if needed. Verify API path (`/api/memos` vs `/api/v1/memos`) matches your Memos version (`MEMOS_API_PATH`).
- **Timer not running:** ensure a `systemd --user` session is active (`systemctl --user status`), run `make enable-timer`, check `journalctl --user -u memo-sync.service`.
- **`jq: command not found` / sync disabled:** install `jq` and `curl`.
- **No notifications:** install `libnotify` (provides `notify-send`), or ignore — capture still works.
- **Empty note:** rejected (whitespace-only input).
- **PATH:** if `memos` not found, add `~/.local/bin` to `PATH`.
- **Planned commands:** `memos list/read/edit/pull/push` currently exit with “not implemented yet”.

## 10. Security Notes

- Treat `MEMOS_TOKEN` as a secret: store only in `~/.config/memo-quick/env` (chmod 600) or a password manager; never commit it (`.env*` ignored except `.env.example` placeholders).
- Use a scoped/limited PAT where possible and rotate if leaked.
- See repo [`.gitignore`](../.gitignore) and [`.env.example`](../.env.example).
