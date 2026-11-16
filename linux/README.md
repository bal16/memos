# Linux quick-capture (Phase 2+)

Unified `memos` CLI (local-first write + API sync + offline queue), Neovim scratchpad flow, and a `systemd --user` timer to flush the queue. Implements PRD §10.2 (baseline) and evolves toward the unified gateway in PRD v0.2.

## Requirements

- `bash`, `curl`, `jq`
- `libnotify` (`notify-send`) — optional notifications
- `neovim` (`nvim`) and `foot` (for scratchpad / compositor keybind)
- `systemd --user` session

## Install / update (from this repo)

```bash
make install   # or: ./scripts/install.sh install
make update    # or: ./scripts/install.sh update
make status
make uninstall
```

Installs to `~/.local/bin/{memos,memo-quick,memo-nvim}` and `~/.config/systemd/user/memo-sync.{service,timer}`, creates `~/notes/memos` and `~/.config/memo-quick/env` (from `.env.example` if missing).

## Configure

Edit `~/.config/memo-quick/env` (chmod 600):

```bash
MEMOS_URL=https://your-memos.vercel.app
MEMOS_TOKEN=<personal-access-token>
# Optional:
# MEMOS_VISIBILITY=PRIVATE|PROTECTED|PUBLIC
# MEMOS_API_PATH=/api/memos        # or /api/v1/memos (auto-tries both if unset)
# MEMOS_NOTES_DIR=$HOME/notes/memos
```

## Usage

```bash
memos                      # open Neovim scratchpad → :wq creates a new note
memos new                  # same (editor if interactive, else stdin/args)
memos "hello world"        # quick-create new note (shorthand)
memos add "hello world"    # quick-create new note
echo "note" | memos add    # quick-create from stdin
memos sync                 # flush ~/notes/memos/.queue.jsonl (alias: flush)
memos completion zsh       # print shell completions (bash|zsh|fish), e.g. source <(memos completion zsh)

# Compatibility wrappers (still installed):
memo-nvim                  # = memos new (editor)
memo-quick "hello"         # = memos add "hello"
memo-quick --flush         # = memos sync
```

Behavior (PRD): appends a timestamped entry to `~/notes/memos/YYYY-MM-DD.md` first, then POSTs to Memos (`/api/memos`, fallback `/api/v1/memos`). On failure, queues JSON to `.queue.jsonl` and `memo-sync.timer` flushes every 5 minutes.

> Planned (PRD v0.2, not yet implemented): `memos list/read/edit/pull/push` and bidirectional sync.

## Compositor / Neovim integration (Phase 3, manual)

- **Niri/Hyprland:** bind `Mod+N` to `foot --app-id=quicknote memos` (or `memo-nvim`) with floating rule (650x400, centered).
- **Neovim (visual):** `vnoremap <leader>mn :w !memos add<CR>` (or keep `:w !memo-quick`)

## Notes

- Daily format: one file per day (`YYYY-MM-DD.md`) with `## HH:MM` entries (create-only append; edit/bidirectional sync is planned).
- API path varies by Memos version; set `MEMOS_API_PATH` if auto-detection fails.
