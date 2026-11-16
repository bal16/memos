# Linux quick-capture (Phase 2)

Implements PRD §10.2: `memo-quick` (local-first write + API sync + offline queue), `memo-nvim` (floating scratchpad), and a `systemd --user` timer to flush the queue.

## Requirements

- `bash`, `curl`, `jq`
- `libnotify` (`notify-send`) — optional notifications
- `neovim` (`nvim`) and `foot` (for `memo-nvim` / compositor keybind)
- `systemd --user` session

## Install / update (from this repo)

```bash
make install   # or: ./scripts/install.sh install
make update    # or: ./scripts/install.sh update
make status
make uninstall
```

Installs to `~/.local/bin/{memo-quick,memo-nvim}` and `~/.config/systemd/user/memo-sync.{service,timer}`, creates `~/notes/memos` and `~/.config/memo-quick/env` (from `.env.example` if missing).

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
memo-quick "hello world"
echo "note" | memo-quick
memo-quick --flush          # drain ~/notes/memos/.queue.jsonl

memo-nvim                   # floating scratchpad (Insert Mode, markdown); :wq sends note
```

Behavior (PRD): appends a timestamped entry to `~/notes/memos/YYYY-MM-DD.md` first, then POSTs to Memos (`/api/memos`, fallback `/api/v1/memos`). On failure, queues JSON to `.queue.jsonl` and `memo-sync.timer` flushes every 5 minutes.

## Compositor / Neovim integration (Phase 3, manual)

- **Niri/Hyprland:** bind `Mod+N` to `foot --app-id=quicknote memo-nvim` with floating rule (650x400, centered).
- **Neovim (visual):** `vnoremap <leader>mn :w !memo-quick<CR>`

## Notes

- Daily format: one file per day (`YYYY-MM-DD.md`) with `## HH:MM` entries (adjust in `memo-quick` if you prefer per-note files).
- API path varies by Memos version; set `MEMOS_API_PATH` if auto-detection fails.
