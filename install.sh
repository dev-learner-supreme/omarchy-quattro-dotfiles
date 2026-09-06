#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles & System Setup
#
# Follows Omarchy Quattro conventions:
#   - omarchy-pkg-add for official packages (Arch + Omarchy repo)
#   - omarchy-pkg-aur-add for AUR packages
#   - omarchy-pkg-missing for idempotent checks
#   - omarchy-hw-fingerprint for hardware detection
#   - omarchy setup security fingerprint for enrollment
#   - omarchy install browser for browser installation
#   - gum confirm for interactive prompts
#   - sudo for privilege escalation in terminal scripts
#
# Usage:
#   ./install.sh          # Interactive mode (prompts for AUR/optional steps)
#   ./install.sh -y       # Unattended mode (accepts all defaults)
# ==============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
ASSUME_YES=0

[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && ASSUME_YES=1

# ---------------------------------------------------------------------------
# Helpers — match Omarchy's own styling conventions
# ---------------------------------------------------------------------------
log()  { echo -e "\e[32m\n$*\e[0m"; }
info() { echo -e "\e[34m:: $*\e[0m"; }
warn() { echo -e "\e[33mWarning: $*\e[0m" >&2; }

confirm() {
  local prompt="$1"
  local default="${2:-true}"
  (( ASSUME_YES )) && return 0

  if [[ -t 0 && -t 1 ]] && command -v gum &>/dev/null; then
    if [[ "$default" == "true" ]]; then
      gum confirm --default=true "$prompt"
    else
      gum confirm --default=false "$prompt"
    fi
  elif [[ -t 0 && -t 1 ]]; then
    local yn
    if [[ "$default" == "true" ]]; then
      read -rp "$prompt [Y/n]: " yn
      [[ -z "$yn" || "$yn" =~ ^[Yy] ]]
    else
      read -rp "$prompt [y/N]: " yn
      [[ "$yn" =~ ^[Yy] ]]
    fi
  else
    # Non-interactive and not --yes: refuse to proceed silently
    warn "Non-interactive terminal; pass -y to accept defaults."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Official Packages (Omarchy repo + Arch core/extra)
# ---------------------------------------------------------------------------
log "Step 1 · Install Official Packages"

# omarchy-pkg-add is idempotent: it calls omarchy-pkg-missing internally and
# uses sudo pacman -S --noconfirm --needed. It also verifies each package
# installed successfully with a pacman -Q post-check.
OFFICIAL_PKGS=(
  omarchy-zsh           # Omarchy repo: zsh + starship + eza + zoxide + fzf + bat + fd + mise + zsh-syntax-highlighting
  zsh-autosuggestions   # extra: fish-like autosuggestions for zsh
  fprintd               # extra: fingerprint enrollment/verify daemon
  usbutils              # core: lsusb for hardware discovery
)

if omarchy-pkg-missing "${OFFICIAL_PKGS[@]}"; then
  info "Installing: ${OFFICIAL_PKGS[*]}"
  omarchy-pkg-add "${OFFICIAL_PKGS[@]}"
else
  info "All required official packages are already installed."
fi

# ---------------------------------------------------------------------------
# Step 2: EgisTec MOC Fingerprint Driver (hardware-detected, AUR)
# ---------------------------------------------------------------------------
log "Step 2 · Check Fingerprint Hardware"

# Use Omarchy's own hardware detection rather than parsing lsusb manually.
if omarchy-hw-fingerprint; then
  info "Fingerprint sensor detected."

  # The SDCP driver is only needed for EgisTec Match-on-Chip sensors.
  # Stock libfprint works fine for Goodix, Synaptics, FPC, Elan, etc.
  # Check the USB bus for the specific EgisTec MOC vendor:product IDs.
  EGISMOC_IDS="1c7a:0582|1c7a:0583|1c7a:0584|1c7a:0586|1c7a:0587|1c7a:05a1|1c7a:05a5"

  if lsusb | grep -qE "$EGISMOC_IDS"; then
    info "EgisTec Match-on-Chip sensor detected — requires SDCP driver."

    if ! pacman -Q libfprint-egismoc-sdcp-git &>/dev/null; then
      echo
      warn "Stock libfprint lacks SDCP support for this sensor."
      warn "Fingerprint enrollments disappear after first verify without the patched driver."
      echo

      if confirm "Install libfprint-egismoc-sdcp-git from AUR? (replaces stock libfprint)" true; then
        # Prefer a pre-compiled binary from the local archive or pacman cache.
        # This avoids the appstreamcli network-test failure during compilation.
        CACHED_PKG=$(find "$HOME/.local/share/packages" /var/cache/pacman/pkg \
          -name "libfprint-egismoc-sdcp-git-*.pkg.tar.zst" 2>/dev/null | head -n 1 || true)

        if [[ -n "$CACHED_PKG" ]]; then
          info "Found pre-compiled package: $CACHED_PKG"
          # --ask=4 answers the "Remove libfprint?" conflict prompt with yes
          sudo pacman -U --noconfirm --ask=4 "$CACHED_PKG"
        else
          info "Compiling from AUR (bypassing appstream network test)..."
          # Remove stock libfprint first (deps-only so fprintd stays)
          if pacman -Q libfprint &>/dev/null && ! pacman -Q libfprint-egismoc-sdcp-git &>/dev/null; then
            sudo pacman -Rdd --noconfirm libfprint
          fi
          yay -S --noconfirm --mflags="--nocheck" libfprint-egismoc-sdcp-git
        fi

        # Lock the driver against updates in /etc/pacman.conf
        if ! grep -q "libfprint-egismoc-sdcp-git" /etc/pacman.conf 2>/dev/null; then
          info "Locking driver in /etc/pacman.conf (IgnorePkg)..."
          sudo sed -i '/^HoldPkg/a IgnorePkg = libfprint libfprint-egismoc-sdcp-git' /etc/pacman.conf
        fi

        # Archive the compiled binary for future offline installs
        BUILT_PKG=$(find "$HOME/.cache/yay/libfprint-egismoc-sdcp-git" \
          -name "libfprint-egismoc-sdcp-git-*-x86_64.pkg.tar.zst" \
          ! -name "*debug*" 2>/dev/null | head -n 1 || true)

        if [[ -n "$BUILT_PKG" ]]; then
          mkdir -p "$HOME/.local/share/packages"
          cp -n "$BUILT_PKG" "$HOME/.local/share/packages/" 2>/dev/null || true
          sudo cp -n "$BUILT_PKG" /var/cache/pacman/pkg/ 2>/dev/null || true
          info "Archived driver binary for offline recovery."
        fi

        sudo systemctl restart fprintd
      fi
    else
      info "EgisTec SDCP driver already installed."

      # Verify the IgnorePkg lock is still in place
      if ! grep -q "libfprint-egismoc-sdcp-git" /etc/pacman.conf 2>/dev/null; then
        warn "IgnorePkg lock missing — re-adding..."
        sudo sed -i '/^HoldPkg/a IgnorePkg = libfprint libfprint-egismoc-sdcp-git' /etc/pacman.conf
      fi
    fi
  fi

  # Offer enrollment if no prints are registered for the current user.
  # Delegates to Omarchy's own setup wizard which handles PAM, polkit,
  # and the lock screen clamshell gate.
  if command -v fprintd-list &>/dev/null; then
    if ! fprintd-list "$USER" 2>/dev/null | grep -q "right-index-finger"; then
      echo
      if confirm "No fingerprint enrolled. Run Omarchy fingerprint setup?" true; then
        omarchy setup security fingerprint || warn "Fingerprint setup did not complete."
      fi
    else
      info "Fingerprint already enrolled for $USER."
    fi
  fi
else
  info "No fingerprint sensor detected — skipping."
fi

# ---------------------------------------------------------------------------
# Step 3: Optional AUR Packages (each prompted individually)
# ---------------------------------------------------------------------------
log "Step 3 · Optional AUR Packages"

# Check AUR accessibility before attempting any AUR operations.
if command -v yay &>/dev/null && omarchy-pkg-aur-accessible; then

  # hyprmoncfg — required for F7 / SUPER+P display layout toggle
  if omarchy-pkg-missing hyprmoncfg; then
    if confirm "[AUR] Install hyprmoncfg? (multi-monitor configurator for F7 key)" false; then
      omarchy-pkg-aur-add hyprmoncfg || warn "Could not install hyprmoncfg"
    fi
  else
    info "hyprmoncfg already installed."
  fi

  # brave-origin-bin — use Omarchy's own browser installer if available
  if omarchy-pkg-missing brave-origin-bin; then
    if confirm "[AUR] Install Brave Origin browser?" false; then
      if command -v omarchy-install-browser &>/dev/null; then
        omarchy install browser brave-origin || warn "Could not install Brave Origin"
      else
        omarchy-pkg-aur-add brave-origin-bin || warn "Could not install brave-origin-bin"
      fi
    fi
  else
    info "brave-origin-bin already installed."
  fi

else
  if ! command -v yay &>/dev/null; then
    warn "yay is not installed — skipping AUR packages."
  else
    warn "AUR is unreachable — skipping AUR packages."
  fi
fi

# ---------------------------------------------------------------------------
# Step 4: Dotfiles Backup & Deployment
# ---------------------------------------------------------------------------
log "Step 4 · Deploy Dotfiles & Configurations"

mkdir -p "$BACKUP_DIR"

sync_item() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"

  # Back up existing non-symlink files before overwriting
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    mkdir -p "$(dirname "$BACKUP_DIR/${dest#$HOME/}")"
    cp -a "$dest" "$BACKUP_DIR/${dest#$HOME/}"
  fi

  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    local item
    for item in "$src"/*; do
      [[ -e "$item" ]] || continue
      sync_item "$item" "$dest/$(basename "$item")"
    done
  else
    cp -a "$src" "$dest"
    info "Deployed: ${dest#$HOME/}"
  fi
}

# .config/* directories
if [[ -d "$DOTFILES_DIR/.config" ]]; then
  for dir in "$DOTFILES_DIR/.config"/*/; do
    [[ -d "$dir" ]] || continue
    sync_item "$dir" "$HOME/.config/$(basename "$dir")"
  done
fi

# .local/* directories
if [[ -d "$DOTFILES_DIR/.local" ]]; then
  for dir in "$DOTFILES_DIR/.local"/*/; do
    [[ -d "$dir" ]] || continue
    sync_item "$dir" "$HOME/.local/$(basename "$dir")"
  done
fi

# Shell rc files
[[ -f "$DOTFILES_DIR/.bashrc" ]] && sync_item "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
[[ -f "$DOTFILES_DIR/.zshrc" ]]  && sync_item "$DOTFILES_DIR/.zshrc"  "$HOME/.zshrc"

# ---------------------------------------------------------------------------
# Step 5: SSH Agent (Arch-native systemd socket activation)
# ---------------------------------------------------------------------------
log "Step 5 · Configure SSH Agent"

# Enable the systemd user socket (idempotent)
if ! systemctl --user is-active --quiet ssh-agent.socket 2>/dev/null; then
  systemctl --user enable --now ssh-agent.socket
  info "Enabled ssh-agent.socket."
else
  info "ssh-agent.socket is already active."
fi

# Session-wide environment variable via environment.d (read by systemd, uwsm, Hyprland)
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/ssh-agent.conf" <<'ENV'
SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
ENV

# Import into the live session so new terminals pick it up immediately
systemctl --user set-environment SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket" 2>/dev/null || true

# Auto-load keys on first use (AddKeysToAgent) — append only if not already configured
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ ! -f "$HOME/.ssh/config" ]] || ! grep -q "AddKeysToAgent" "$HOME/.ssh/config" 2>/dev/null; then
  cat >> "$HOME/.ssh/config" <<'SSHCONF'
Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
SSHCONF
  chmod 600 "$HOME/.ssh/config"
  info "Configured ~/.ssh/config (AddKeysToAgent yes)."
else
  info "~/.ssh/config already has AddKeysToAgent."
fi

# ---------------------------------------------------------------------------
# Step 6: Omarchy Shell Plugins
# ---------------------------------------------------------------------------
log "Step 6 · Omarchy Shell Plugins"

PLUGINS=(
  "https://github.com/ax1g/quickshell-screentime-plugin.git"
  "https://github.com/crmne/omarchy-hyprmoncfg.git"
  "https://github.com/ssupt/omarchy-bluetooth-audio.git"
)

for plugin_url in "${PLUGINS[@]}"; do
  # omarchy plugin add exits non-zero if already installed; that is expected
  info "Plugin: $plugin_url"
  omarchy plugin add "$plugin_url" --enable --yes 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Step 7: Reload Desktop Services
# ---------------------------------------------------------------------------
log "Step 7 · Reload Services"

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart wireplumber 2>/dev/null || true

if command -v hyprctl &>/dev/null; then
  hyprctl reload 2>/dev/null || true
  info "Hyprland reloaded."
fi

if command -v omarchy &>/dev/null; then
  omarchy restart shell 2>/dev/null || true
  info "Omarchy shell restarted."
fi

# Clean up empty backup directory
if [[ -d "$BACKUP_DIR" ]] && [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  rmdir "$BACKUP_DIR" 2>/dev/null || true
elif [[ -d "$BACKUP_DIR" ]]; then
  info "Previous configs backed up to: $BACKUP_DIR"
fi

log "Setup complete!"
