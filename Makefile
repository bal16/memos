PREFIX       ?= $(HOME)/.local
BINDIR       ?= $(PREFIX)/bin
CONFIG_DIR   ?= $(XDG_CONFIG_HOME)
ifeq ($(strip $(CONFIG_DIR)),)
CONFIG_DIR   := $(HOME)/.config
endif
SYSTEMD_USER ?= $(CONFIG_DIR)/systemd/user
MEMO_CONFIG  ?= $(CONFIG_DIR)/memo-quick
NOTES_DIR    ?= $(HOME)/notes/memos

BIN_SRC      := linux/bin
UNIT_SRC     := linux/systemd
SHELL_SRCS   := $(BIN_SRC)/memo-quick $(BIN_SRC)/memo-nvim scripts/install.sh

.PHONY: install update uninstall enable-timer disable-timer status help lint fmt fmt-check check quality

help:
	@echo "Targets:"
	@echo "  install update uninstall enable-timer disable-timer status"
	@echo "  lint fmt fmt-check check quality"

install: update enable-timer
	@mkdir -p "$(MEMO_CONFIG)" "$(NOTES_DIR)"
	@if [ ! -f "$(MEMO_CONFIG)/env" ]; then \
		install -Dm600 .env.example "$(MEMO_CONFIG)/env"; \
		echo "Created $(MEMO_CONFIG)/env from .env.example - edit MEMOS_URL and MEMOS_TOKEN"; \
	else \
		echo "Keeping existing $(MEMO_CONFIG)/env"; \
	fi
	@echo "Install complete."

update:
	@install -Dm755 "$(BIN_SRC)/memo-quick" "$(BINDIR)/memo-quick"
	@install -Dm755 "$(BIN_SRC)/memo-nvim" "$(BINDIR)/memo-nvim"
	@install -Dm644 "$(UNIT_SRC)/memo-sync.service" "$(SYSTEMD_USER)/memo-sync.service"
	@install -Dm644 "$(UNIT_SRC)/memo-sync.timer" "$(SYSTEMD_USER)/memo-sync.timer"
	@mkdir -p "$(NOTES_DIR)"
	@systemctl --user daemon-reload 2>/dev/null || true
	@systemctl --user try-restart memo-sync.timer 2>/dev/null || true
	@echo "Updated binaries and systemd units."

enable-timer:
	@systemctl --user daemon-reload 2>/dev/null || true
	@systemctl --user enable --now memo-sync.timer 2>/dev/null || echo "Note: could not enable/start timer (no user systemd session?)"

disable-timer:
	@systemctl --user disable --now memo-sync.timer 2>/dev/null || true

uninstall: disable-timer
	@rm -f "$(BINDIR)/memo-quick" "$(BINDIR)/memo-nvim"
	@rm -f "$(SYSTEMD_USER)/memo-sync.service" "$(SYSTEMD_USER)/memo-sync.timer"
	@systemctl --user daemon-reload 2>/dev/null || true
	@echo "Removed binaries and units (kept $(MEMO_CONFIG) and $(NOTES_DIR))"

status:
	@echo "Binaries:"; ls -l "$(BINDIR)/memo-quick" "$(BINDIR)/memo-nvim" 2>/dev/null || true
	@echo "Config: $(MEMO_CONFIG)/env"; echo "Notes:  $(NOTES_DIR)"
	@systemctl --user status memo-sync.timer --no-pager 2>/dev/null || echo "timer: inactive/unavailable"

lint:
	@echo "==> bash -n"
	@bash -n $(SHELL_SRCS)
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "==> shellcheck"; shellcheck -x $(SHELL_SRCS); \
	else \
		echo "==> shellcheck: not installed (skipped)"; \
	fi
	@if command -v hadolint >/dev/null 2>&1; then \
		echo "==> hadolint"; hadolint Dockerfile; \
	else \
		echo "==> hadolint: not installed (skipped)"; \
	fi

fmt:
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "==> shfmt -w"; shfmt -w -i 2 -ci -sr $(SHELL_SRCS); \
	else \
		echo "==> shfmt: not installed (skipped)"; \
	fi

fmt-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "==> shfmt -d"; shfmt -d -i 2 -ci -sr $(SHELL_SRCS); \
	else \
		echo "==> shfmt: not installed (skipped)"; \
	fi

check: lint fmt-check
	@echo "==> check: ok"

quality: check
	@echo "==> quality: ok"
