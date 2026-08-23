#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles Installer & Synchronization Script
# ==============================================================================
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false

usage() {
  cat << 'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  -n, --dry-run    Simulate installation without making changes or writing files
  -h, --help       Display this help message
EOF
  exit 0
}

# Parse command line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf '\033[31mError:\033[0m Unknown option: %s\n' "$1" >&2
      usage
      ;;
  esac
done

log() { printf '\033[32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[34m::\033[0m %s\n' "$*"; }
dry() { printf '\033[35m[DRY-RUN]\033[0m %s\n' "$*"; }

if [[ "$DRY_RUN" == true ]]; then
  log "Running in DRY-RUN mode (simulation only, no files will be changed)..."
fi

# 1. Back up and sync configuration files
sync_item() {
  local src="$1"
  local dest="$2"

  if [[ "$DRY_RUN" == true ]]; then
    if [[ -d "$src" ]]; then
      find "$src" -maxdepth 1 -mindepth 1 | while read -r item; do
        local name="$(basename "$item")"
        sync_item "$item" "$dest/$name"
      done
    else
      if [[ -e "$dest" && ! -L "$dest" ]]; then
        dry "Would backup: ${dest#$HOME/} -> ${BACKUP_DIR#$HOME/}/${dest#$HOME/}"
      fi
      dry "Would install: ${dest#$HOME/}"
    fi
    return 0
  fi

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

if [[ "$DRY_RUN" == false ]]; then
  log "Starting Omarchy Quattro Configuration Sync..."
  mkdir -p "$BACKUP_DIR"
fi

log "Deploying user configurations..."
# Sync .config files
find "$DOTFILES_DIR/.config" -maxdepth 1 -mindepth 1 | while read -r dir; do
  name="$(basename "$dir")"
  sync_item "$dir" "$HOME/.config/$name"
done

# Sync .local files
if [[ -d "$DOTFILES_DIR/.local" ]]; then
  find "$DOTFILES_DIR/.local" -maxdepth 1 -mindepth 1 | while read -r dir; do
    name="$(basename "$dir")"
    sync_item "$dir" "$HOME/.local/$name"
  done
fi

# Sync shell rc files
[[ -f "$DOTFILES_DIR/.bashrc" ]] && sync_item "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
[[ -f "$DOTFILES_DIR/.zshrc" ]] && sync_item "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

log "Checking Omarchy Shell Plugins..."
PLUGINS=(
  "https://github.com/ax1g/quickshell-screentime-plugin.git"
  "https://github.com/crmne/omarchy-hyprmoncfg.git"
  "https://github.com/Aryan-Techie/omarchy-todoist.git"
  "https://github.com/dev-learner-supreme/omarchy-notification-center.git"
  "https://github.com/ssupt/omarchy-bluetooth-audio.git"
)

for plugin_url in "${PLUGINS[@]}"; do
  if [[ "$DRY_RUN" == true ]]; then
    dry "Would add & enable plugin: $plugin_url"
  else
    info "Adding plugin: $plugin_url"
    omarchy plugin add "$plugin_url" --enable --yes 2>/dev/null || true
  fi
done

log "Checking AUR packages..."
if command -v yay &>/dev/null; then
  for pkg in hyprmoncfg brave-origin-bin; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
      if [[ "$DRY_RUN" == true ]]; then
        dry "Would install AUR package via yay: $pkg"
      else
        info "Installing optional package: $pkg"
        yay -S --noconfirm "$pkg" || warn "Could not install $pkg"
      fi
    else
      info "Package already installed: $pkg"
    fi
  done
else
  info "yay not detected; skipping AUR package checks."
fi

log "Checking service reloads..."
if [[ "$DRY_RUN" == true ]]; then
  dry "Would run: systemctl --user daemon-reload"
  dry "Would run: systemctl --user restart wireplumber"
  dry "Would run: hyprctl reload"
  dry "Would run: omarchy restart shell"
else
  systemctl --user daemon-reload || true
  systemctl --user restart wireplumber || true
  if command -v hyprctl &>/dev/null; then
    hyprctl reload || true
  fi
  if command -v omarchy &>/dev/null; then
    omarchy restart shell 2>/dev/null || true
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  log "Dry run complete! No changes were made."
else
  log "Installation complete!"
  if [[ -d "$BACKUP_DIR" && $(ls -A "$BACKUP_DIR") ]]; then
    info "Previous configurations backed up to: $BACKUP_DIR"
  fi
fi
