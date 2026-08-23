#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles Installer & Synchronization Script
# ==============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[34m::\033[0m %s\n' "$*"; }

# 1. Back up and sync configuration files
sync_item() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" && ! -L "$dest" ]]; then
    mkdir -p "$(dirname "$BACKUP_DIR/${dest#$HOME/}")"
    cp -a "$dest" "$BACKUP_DIR/${dest#$HOME/}"
  fi

  # Create directories or copy/link files
  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    find "$src" -maxdepth 1 -mindepth 1 | while read -r item; do
      local name="$(basename "$item")"
      sync_item "$item" "$dest/$name"
    done
  else
    cp -a "$src" "$dest"
    info "Installed: ${dest#$HOME/}"
  fi
}

log "Starting Omarchy Quattro Configuration Sync..."
mkdir -p "$BACKUP_DIR"

log "Deploying user configurations..."
# Sync .config files
find "$DOTFILES_DIR/.config" -maxdepth 1 -mindepth 1 | while read -r dir; do
  local name="$(basename "$dir")"
  sync_item "$dir" "$HOME/.config/$name"
done

# Sync .local files
if [[ -d "$DOTFILES_DIR/.local" ]]; then
  find "$DOTFILES_DIR/.local" -maxdepth 1 -mindepth 1 | while read -r dir; do
    local name="$(basename "$dir")"
    sync_item "$dir" "$HOME/.local/$name"
  done
fi

# Sync shell rc files
[[ -f "$DOTFILES_DIR/.bashrc" ]] && sync_item "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
[[ -f "$DOTFILES_DIR/.zshrc" ]] && sync_item "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

log "Installing & Enabling Omarchy Shell Plugins..."
PLUGINS=(
  "https://github.com/ax1g/quickshell-screentime-plugin.git"
  "https://github.com/crmne/omarchy-hyprmoncfg.git"
  "https://github.com/Aryan-Techie/omarchy-todoist.git"
  "https://github.com/dev-learner-supreme/omarchy-notification-center.git"
  "https://github.com/ssupt/omarchy-bluetooth-audio.git"
)

for plugin_url in "${PLUGINS[@]}"; do
  info "Adding plugin: $plugin_url"
  omarchy plugin add "$plugin_url" --enable --yes 2>/dev/null || true
done

log "Checking AUR packages..."
if command -v yay &>/dev/null; then
  for pkg in hyprmoncfg brave-origin-bin; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
      info "Installing optional package: $pkg"
      yay -S --noconfirm "$pkg" || warn "Could not install $pkg"
    fi
  done
fi

log "Reloading services..."
systemctl --user daemon-reload || true
systemctl --user restart wireplumber || true
if command -v hyprctl &>/dev/null; then
  hyprctl reload || true
fi
if command -v omarchy &>/dev/null; then
  omarchy restart shell 2>/dev/null || true
fi

log "Installation complete!"
if [[ -d "$BACKUP_DIR" && $(ls -A "$BACKUP_DIR") ]]; then
  info "Previous configurations backed up to: $BACKUP_DIR"
fi
