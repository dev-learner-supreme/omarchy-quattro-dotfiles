#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles & System Setup
#
# Uses Omarchy's own tooling wherever it exists, so the result matches what the
# Omarchy menu would do:
#   omarchy-pkg-add / omarchy-pkg-aur-add   packages (idempotent)
#   omarchy install terminal / default terminal
#   omarchy-hw-fingerprint                  sensor detection
#   omarchy setup security fingerprint      non-EgisTec sensors
#   omarchy plugin clone / enable           lock-screen customization
#   ~/.config/omarchy/hooks/*.d             update/boot automation
#
# EgisTec Match-on-Chip fingerprint handling lives in bin/egismoc-fingerprint
# (linked to ~/.local/bin), so it can be re-run on its own and from the menu.
#
# Usage:
#   ./install.sh          # interactive
#   ./install.sh -y       # unattended: each prompt takes its default answer
# ==============================================================================
set -Eeuo pipefail

if [[ $EUID -eq 0 ]]; then
  echo -e "\e[31mError: run this as your regular user, not with sudo — it asks for sudo when needed.\e[0m" >&2
  exit 1
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
ASSUME_YES=0
# shellcheck source=lib/ui.sh
source "$DOTFILES_DIR/lib/ui.sh"

for arg in "$@"; do
  case "$arg" in
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) sed -n '17,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         echo "Usage: $0 [-y|--yes] [-h|--help]" >&2; exit 2 ;;
  esac
done

on_error() {
  local code=$?
  trap - ERR
  echo -e "\e[31m\nFailed at line $1 (exit $code).\e[0m" >&2
  exit "$code"
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------------
# Lockfile — one run at a time; a lock left by a killed run is cleared by PID.
# ---------------------------------------------------------------------------
LOCK_DIR="$HOME/.cache/omarchy-dotfiles-install.lock"
LOCK_OWNED=0
mkdir -p "$(dirname "$LOCK_DIR")"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -z "$lock_pid" ]]; then
    fail "Found $LOCK_DIR with no owner PID. If no other install.sh is running, remove it and re-run."
  elif kill -0 "$lock_pid" 2>/dev/null; then
    fail "Another instance of install.sh is running (PID $lock_pid)."
  fi
  warn "Clearing stale lock left by PID $lock_pid (no longer running)."
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || fail "Could not acquire $LOCK_DIR."
fi
echo "$$" > "$LOCK_DIR/pid"
LOCK_OWNED=1

cleanup() {
  stop_sudo_keepalive
  (( LOCK_OWNED )) && rm -rf "$LOCK_DIR"
  return 0
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Environment guards
# ---------------------------------------------------------------------------
command -v omarchy-pkg-add &>/dev/null ||
  fail "This needs an Omarchy install (omarchy.org) — omarchy-pkg-add not found."

OMARCHY_VERSION="$(omarchy-version 2>/dev/null || true)"
if [[ -z "$OMARCHY_VERSION" ]]; then
  warn "Could not read the Omarchy version; Quattro-specific steps may no-op."
elif [[ "$OMARCHY_VERSION" =~ ^[0-3]\. ]]; then
  warn "Omarchy $OMARCHY_VERSION looks pre-Quattro; this setup assumes 4.x (Quickshell shell, Lua Hyprland config)."
  confirm "Continue anyway?" false || fail "Aborted."
else
  info "Omarchy $OMARCHY_VERSION"
fi

if (( ! ASSUME_YES )) && [[ ! -t 0 ]]; then
  fail "No terminal for prompts. Run ./install.sh from a terminal, or pass -y for defaults."
fi
start_sudo_keepalive

# ---------------------------------------------------------------------------
# Step 1 · Packages
# ---------------------------------------------------------------------------
log "Step 1 · Packages"

OFFICIAL_PKGS=(
  omarchy-zsh           # zsh + starship + eza + zoxide + fzf + bat + fd + mise + syntax highlighting
  zsh-autosuggestions   # fish-like autosuggestions
  usbutils              # lsusb for hardware discovery
  restic                # backup engine behind Omarchy Time Machine
  rclone                # cloud backends (Google Drive, B2, S3)
)
if omarchy-pkg-missing "${OFFICIAL_PKGS[@]}"; then
  omarchy-pkg-add "${OFFICIAL_PKGS[@]}"
else
  info "Official packages already installed."
fi

# Ghostty as the default terminal, the way Setup > Defaults > Terminal does it.
if omarchy-pkg-missing ghostty; then
  omarchy-install-terminal ghostty || warn "Could not install Ghostty."
elif [[ "$(omarchy-default-terminal 2>/dev/null || true)" != "ghostty" ]]; then
  omarchy-default-terminal ghostty || warn "Could not make Ghostty the default terminal."
else
  info "Ghostty is already the default terminal."
fi

# ---------------------------------------------------------------------------
# Step 2 · Dotfiles (before fingerprint, so a tracked shell.json can't undo the
# lock-screen clone that Step 3 enables)
# ---------------------------------------------------------------------------
log "Step 2 · Deploy Dotfiles"

mkdir -p "$BACKUP_DIR"

sync_item() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"

  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    local item
    for item in "$src"/*; do
      [[ -e "$item" ]] || continue
      sync_item "$item" "$dest/$(basename "$item")"
    done
    return 0
  fi

  [[ -f "$dest" ]] && cmp -s "$src" "$dest" && return 0
  if [[ -f "$dest" && ! -L "$dest" ]]; then
    mkdir -p "$(dirname "$BACKUP_DIR/${dest#"$HOME"/}")"
    cp -a "$dest" "$BACKUP_DIR/${dest#"$HOME"/}"
  fi
  cp -a "$src" "$dest"
  info "Deployed: ${dest#"$HOME"/}"
}

for dir in "$DOTFILES_DIR/.config"/*/ "$DOTFILES_DIR/.local"/*/; do
  [[ -d "$dir" ]] || continue
  parent="$(basename "$(dirname "$dir")")"
  sync_item "$dir" "$HOME/$parent/$(basename "$dir")"
done
[[ -f "$DOTFILES_DIR/.bashrc" ]] && sync_item "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
[[ -f "$DOTFILES_DIR/.zshrc" ]]  && sync_item "$DOTFILES_DIR/.zshrc"  "$HOME/.zshrc"

# Linked, not copied: the command finds the pinned PKGBUILD and archived
# driver through its real path in this repo.
mkdir -p "$HOME/.local/bin"
ln -sfn "$DOTFILES_DIR/bin/egismoc-fingerprint" "$HOME/.local/bin/egismoc-fingerprint"

# ---------------------------------------------------------------------------
# Step 3 · Fingerprint
# ---------------------------------------------------------------------------
log "Step 3 · Fingerprint"

fingerprint_args=(setup)
(( ASSUME_YES )) && fingerprint_args+=(-y)

if ! omarchy-hw-fingerprint; then
  info "No fingerprint sensor detected — skipping."
elif "$DOTFILES_DIR/bin/egismoc-fingerprint" detect >/dev/null; then
  # A failure here shouldn't block the rest of the setup; it's re-runnable.
  EGISMOC_PAM_BACKUP_DIR="$BACKUP_DIR/pam" "$DOTFILES_DIR/bin/egismoc-fingerprint" "${fingerprint_args[@]}" ||
    warn "Fingerprint setup didn't finish. Re-run any time: egismoc-fingerprint setup"
elif omarchy-pkg-present fprintd; then
  info "Fingerprint already set up through Omarchy."
elif (( ASSUME_YES )); then
  info "Fingerprint sensor found. Set it up later with: omarchy setup security fingerprint"
elif confirm "Set up the fingerprint sensor with Omarchy's own wizard now?" true; then
  omarchy-setup-security-fingerprint || warn "Omarchy's fingerprint setup didn't finish."
fi

# ---------------------------------------------------------------------------
# Step 4 · Optional AUR packages
# ---------------------------------------------------------------------------
log "Step 4 · Optional AUR Packages"

if ! command -v yay &>/dev/null; then
  warn "yay is not installed — skipping AUR packages."
elif ! omarchy-pkg-aur-accessible; then
  warn "AUR is unreachable — skipping AUR packages."
else
  if omarchy-pkg-present hyprmoncfg; then
    info "hyprmoncfg already installed."
  elif confirm "[AUR] Install hyprmoncfg? (multi-monitor configurator for F7)" false; then
    omarchy-pkg-aur-add hyprmoncfg || warn "Could not install hyprmoncfg."
  fi

  if omarchy-pkg-present brave-origin-bin; then
    info "Brave Origin already installed."
  elif confirm "[AUR] Install Brave Origin browser?" false; then
    omarchy-install-browser brave-origin || warn "Could not install Brave Origin."
  fi
fi

# ---------------------------------------------------------------------------
# Step 5 · SSH agent (systemd socket activation; Omarchy has no helper for it)
# ---------------------------------------------------------------------------
log "Step 5 · SSH Agent"

if systemctl --user is-active --quiet ssh-agent.socket 2>/dev/null; then
  info "ssh-agent.socket is already active."
else
  systemctl --user enable --now ssh-agent.socket
  info "Enabled ssh-agent.socket."
fi

mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/ssh-agent.conf" <<'ENV'
SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
ENV
systemctl --user set-environment SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket" 2>/dev/null || true

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if grep -q "AddKeysToAgent" "$HOME/.ssh/config" 2>/dev/null; then
  info "SSH config already has AddKeysToAgent."
else
  cat >> "$HOME/.ssh/config" <<'SSHCONF'
Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
SSHCONF
  chmod 600 "$HOME/.ssh/config"
  info "Configured ~/.ssh/config (AddKeysToAgent yes)."
fi

# ---------------------------------------------------------------------------
# Step 6 · Reload
# ---------------------------------------------------------------------------
log "Step 6 · Reload"

systemctl --user daemon-reload 2>/dev/null || true
# A plain restart applies the WirePlumber rules; `omarchy restart audio` is a
# recovery tool that also resets USB audio state, which isn't wanted here.
systemctl --user restart wireplumber 2>/dev/null || true

if command -v hyprctl &>/dev/null; then
  hyprctl reload >/dev/null 2>&1 || true
  config_errors="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -n "$config_errors" && "$config_errors" != *"no errors"* ]]; then
    warn "Hyprland reported config errors:"
    echo "$config_errors" >&2
  else
    info "Hyprland reloaded cleanly."
  fi
fi

omarchy-restart-terminal >/dev/null 2>&1 || true
if omarchy-restart-shell 2>/dev/null; then
  info "Omarchy shell restarted."
else
  warn "Omarchy shell not restarted (the session may be locked) — run: omarchy restart shell"
fi

if [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  rmdir "$BACKUP_DIR" 2>/dev/null || true
else
  info "Replaced files backed up to: $BACKUP_DIR"
fi

log "Setup complete!"
