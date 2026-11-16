# Linux quick-capture & sync (Phase 5/6 foundation)

Unified `memos` CLI with local per-note mirror (`notes/*.md` + frontmatter), outbound queue, and Memos API sync (pull/list/read/create/edit/delete). Implements PRD v0.2 foundation (hardening in progress).

## Requirements

- `bash`, `curl`, `jq`
- `libnotify` (`notify-send`) — optional
- `neovim` (`nvim`) — for `new`/`edit`
- `systemd --user` session

## Install / update

```bash
make install   # or: ./scripts/install.sh install
make update
make status
```

Installs `~/.local/bin/{memos,memo-quick,memo-nvim}` and `~/.config/systemd/user/memo-sync.{service,timer}`.

## Configure

Edit `~/.config/memo-quick/env` (chmod 600):

```bash
MEMOS_URL=https://your-memos.vercel.app
MEMOS_TOKEN=<personal-access-token>
# Optional:
# MEMOS_VISIBILITY=PRIVATE|PROTECTED|PUBLIC
# MEMOS_API_PATH=                 # force API root (e.g. /api or /api/v1); auto-detected if unset
# MEMOS_NOTES_DIR=$HOME/notes/memos
```

## Usage

```bash
memos                      # Neovim scratchpad → create new note
memos "hello world"        # quick-create (shorthand)
memos add "hello world"    # quick-create
echo "note" | memos add

memos pull                 # pull remote memos into local mirror
memos list                 # list local mirror (or --remote)
memos read <ref>           # show note (uid/name/prefix)
memos edit <ref>           # edit in $EDITOR and push update
memos rm <ref>             # delete note (alias: delete)
memos sync                 # push dirty + flush outbound queue + pull
memos flush                # flush/push outbound queue only
memos completion zsh       # source <(memos completion zsh)

# Compatibility wrappers: memo-nvim, memo-quick
```

## Storage model (mirror)

- `~/notes/memos/notes/<uid>.md` — **one file per memo** with YAML frontmatter (`name`, `uid`, `visibility`, `createTime`, `updateTime`, `state`) and content body.
- `~/notes/memos/.sync/state.json` — sync state/id mapping.
- `~/notes/memos/.queue.jsonl` — outbound operation queue (create/update when offline or on failure).

**Recommendation/design (Phase 5/6):** per-note mirror files (stable ID mapping) are the canonical local representation for sync/edit. New captures create mirror files. Run `memos pull` to populate mirror from cloud (authoritative). Existing legacy daily logs `YYYY-MM-DD.md` (append-only, pre-mirror) are **not** auto-migrated/mapped to remote IDs (to avoid duplicates); keep them as archive/reference if present.

## Notes

- `memos sync` = push dirty notes + flush queued ops (create/update/delete) + pull (bidirectional foundation).
- Delete propagation: `memos rm` deletes locally+remotely (or queues); `pull` removes locally if a previously-synced remote note is gone (keeps local and marks conflict if locally modified).
- Conflict handling: concurrent edits may keep local and save remote as `*.remote-conflict-*` (no merge UI yet). Sync scope (tags/pin/attachments/visibility/state) and incremental reconciliation are still evolving (see PRD v0.2).
- API routes auto-detected (`/api` + `/memos` vs `/api/v1`); set `MEMOS_API_PATH` and/or `MEMOS_DEBUG=1` if needed.
