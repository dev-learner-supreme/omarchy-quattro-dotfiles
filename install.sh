#!/usr/bin/env bash
# ==============================================================================
# Omarchy Quattro Dotfiles & System Setup
#
# Follows Omarchy Quattro conventions:
#   - omarchy-pkg-add for official packages (Arch + Omarchy repo)
#   - omarchy-pkg-aur-add for AUR packages
#   - omarchy-pkg-missing for idempotent checks
#   - omarchy-hw-fingerprint for hardware detection
#   - fprintd-enroll for hardware fingerprint enrollment
#   - omarchy install browser for browser installation
#   - omarchy install terminal for terminal installation
#   - gum confirm for interactive prompts
#   - sudo for privilege escalation in terminal scripts
#
# Usage:
#   ./install.sh          # Interactive mode (prompts for AUR/optional steps)
#   ./install.sh -y       # Unattended mode (accepts all defaults)
#
# Safety notes:
#   - Refuses to run if Omarchy itself isn't detected, and warns (doesn't
#     block) if the detected version looks pre-Quattro.
#   - Refuses to run two copies of itself concurrently.
#   - Keeps sudo alive for the duration of the run instead of letting the
#     timestamp expire mid-script.
#   - Backs up /etc/pam.d/sudo and /etc/pam.d/polkit-1 before editing them,
#     and automatically restores them if anything fails partway through.
#   - Tracks a sha256 for the cached fingerprint driver binary and refuses
#     to silently overwrite the archived copy if it ever changes unexpectedly.
#   - Confirms sudo still works at the very end, before you close the terminal.
# ==============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

# Ensure script is run as normal user, not via sudo/root
if [[ $EUID -eq 0 ]]; then
  echo -e "\e[31mError: Do not run this script with sudo or as root!\e[0m" >&2
  echo -e "\e[33mPlease run it as your regular user: ./install.sh\e[0m" >&2
  echo -e "The script will prompt for sudo when elevated permissions are needed." >&2
  exit 1
fi

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
PAM_BACKUP_DIR="$BACKUP_DIR/pam"
ASSUME_YES=0

[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && ASSUME_YES=1

# ---------------------------------------------------------------------------
# Helpers — match Omarchy's own styling conventions
# ---------------------------------------------------------------------------
log()  { echo -e "\e[32m\n$*\e[0m"; }
info() { echo -e "\e[34m:: $*\e[0m"; }
warn() { echo -e "\e[33mWarning: $*\e[0m" >&2; }
fail() { echo -e "\e[31mError: $*\e[0m" >&2; exit 1; }

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
# PAM backup/restore — shared by the error trap and Step 2
# ---------------------------------------------------------------------------
restore_pam_backup() {
  [[ -f "$PAM_BACKUP_DIR/sudo" ]] && sudo cp "$PAM_BACKUP_DIR/sudo" /etc/pam.d/sudo
  [[ -f "$PAM_BACKUP_DIR/polkit-1" ]] && sudo cp "$PAM_BACKUP_DIR/polkit-1" /etc/pam.d/polkit-1
  [[ -f "$PAM_BACKUP_DIR/.polkit-1-created" ]] && sudo rm -f /etc/pam.d/polkit-1
  info "PAM files restored from $PAM_BACKUP_DIR."
}

# ---------------------------------------------------------------------------
# Error trap — prints the failing line instead of dying silently, and rolls
# back PAM edits automatically if a backup exists (i.e. Step 2 was mid-flight).
# ---------------------------------------------------------------------------
on_error() {
  local exit_code=$?
  local line_no=$1
  echo -e "\e[31m\nScript failed at line $line_no (exit code $exit_code).\e[0m" >&2
  if [[ -d "${PAM_BACKUP_DIR:-}" ]] && [[ -n "$(ls -A "$PAM_BACKUP_DIR" 2>/dev/null)" ]]; then
    warn "Restoring /etc/pam.d/sudo and /etc/pam.d/polkit-1 from backup due to failure..."
    restore_pam_backup
  fi
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------------
# Lockfile — refuse to run two copies of this script at once
# ---------------------------------------------------------------------------
LOCK_DIR="$HOME/.cache/omarchy-dotfiles-install.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "Another instance of install.sh appears to be running (found $LOCK_DIR). Remove it manually if that's not the case."
fi

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  if [[ -d "${LOCK_DIR:-}" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Environment guards — confirm this is actually an Omarchy install, and
# warn (without blocking) if the detected version looks pre-Quattro, since
# Step 6 below assumes Quattro's Quickshell-based `omarchy restart shell`.
# ---------------------------------------------------------------------------
command -v pacman &>/dev/null || fail "pacman not found — this script only supports Arch-based Omarchy installs."

if ! command -v omarchy-pkg-add &>/dev/null; then
  fail "omarchy-pkg-add not found. This script requires an Omarchy installation (omarchy.org) — it will not work on plain Arch."
fi

OMARCHY_DETECTED_VERSION=""
if command -v omarchy &>/dev/null; then
  OMARCHY_DETECTED_VERSION="$(omarchy version 2>/dev/null || true)"
fi

if [[ -n "$OMARCHY_DETECTED_VERSION" ]]; then
  info "Detected Omarchy version: $OMARCHY_DETECTED_VERSION"
  if [[ "$OMARCHY_DETECTED_VERSION" =~ ^[0-3]\. ]]; then
    warn "This script assumes Omarchy Quattro (4.x) conventions (Quickshell restart, environment.d, etc.)."
    warn "Detected version looks pre-Quattro — Step 6 (Reload Services) may not behave as expected."
    confirm "Continue anyway?" false || fail "Aborted by user."
  fi
else
  warn "Could not determine Omarchy version (omarchy version returned nothing). Proceeding, but Quattro-specific steps may silently no-op."
fi

# Keep sudo alive for the whole run instead of letting the timestamp expire
# mid-script and re-prompting unexpectedly. Killed automatically on exit via cleanup().
sudo -v
( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!

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
  usbutils              # core: lsusb for hardware discovery
  restic                # extra: deduplicating backup tool (Omarchy Time Machine backend)
  rclone                # extra: cloud storage sync (Google Drive, B2, S3 backend for Time Machine)
)

if omarchy-pkg-missing "${OFFICIAL_PKGS[@]}"; then
  info "Installing: ${OFFICIAL_PKGS[*]}"
  omarchy-pkg-add "${OFFICIAL_PKGS[@]}"
else
  info "All required official packages are already installed."
fi

# Terminal: Ghostty via Omarchy installer
if omarchy-pkg-missing ghostty; then
  info "Installing Ghostty terminal via Omarchy..."
  omarchy install terminal ghostty || warn "Could not install ghostty via omarchy install"
else
  info "Ghostty terminal is already installed."
  # Ensure ghostty is set as the default in xdg-terminals.list if missing
  mkdir -p "$HOME/.config"
  if [[ ! -f "$HOME/.config/xdg-terminals.list" ]] || ! grep -q "ghostty" "$HOME/.config/xdg-terminals.list" 2>/dev/null; then
    cat > "$HOME/.config/xdg-terminals.list" <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
com.mitchellh.ghostty.desktop
EOF
    info "Configured Ghostty as default in xdg-terminals.list."
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: EgisTec MOC Fingerprint Driver & Authentication
# ---------------------------------------------------------------------------
log "Step 2 · Check Fingerprint Hardware"

HAS_EGISMOC=0

archive_driver_pkg() {
  local pkg="$1"
  [[ -n "$pkg" && -f "$pkg" ]] || return 0
  mkdir -p "$DOTFILES_DIR/packages" "$HOME/.local/share/packages"

  # Track a checksum for the archived binary. If a future run finds a
  # differently-hashed package under the same filename, refuse to silently
  # overwrite the archived copy — that shouldn't happen with a pinned AUR
  # git package and is worth a human looking at.
  local checksum_file="$DOTFILES_DIR/packages/.sha256sums"
  local pkg_name pkg_hash recorded_hash=""
  pkg_name="$(basename "$pkg")"
  pkg_hash="$(sha256sum "$pkg" | awk '{print $1}')"

  if [[ -f "$checksum_file" ]]; then
    recorded_hash="$(grep -F " $pkg_name" "$checksum_file" 2>/dev/null | awk '{print $1}' || true)"
    if [[ -n "$recorded_hash" ]]; then
      if [[ "$recorded_hash" != "$pkg_hash" ]]; then
        warn "Checksum mismatch for $pkg_name vs. previously archived copy — NOT overwriting automatically."
        warn "Verify this binary manually before trusting it (recorded: ${recorded_hash:0:12}..., now: ${pkg_hash:0:12}...)."
        return 0
      fi
      # Recorded hash matches current binary hash — avoid appending duplicate entries
    fi
  fi

  if [[ -z "$recorded_hash" ]]; then
    echo "$pkg_hash $pkg_name" >> "$checksum_file"
  fi
  cp -n "$pkg" "$DOTFILES_DIR/packages/" 2>/dev/null || true
  cp -n "$pkg" "$HOME/.local/share/packages/" 2>/dev/null || true
  sudo cp -n "$pkg" /var/cache/pacman/pkg/ 2>/dev/null || true
  info "Archived driver binary for offline recovery (sha256: ${pkg_hash:0:12}...)."
}

lock_pacman_driver() {
  local conf="/etc/pacman.conf"
  [[ -f "$conf" ]] || return 0
  if ! grep -q "libfprint-egismoc-sdcp-git" "$conf" 2>/dev/null; then
    info "Locking driver in /etc/pacman.conf (IgnorePkg)..."
    if grep -q "^[[:space:]]*IgnorePkg" "$conf"; then
      sudo sed -i '/^[[:space:]]*IgnorePkg/s/$/ libfprint libfprint-egismoc-sdcp-git/' "$conf"
    elif grep -q "^[[:space:]]*HoldPkg" "$conf"; then
      sudo sed -i '/^[[:space:]]*HoldPkg/a IgnorePkg = libfprint libfprint-egismoc-sdcp-git' "$conf"
    elif grep -q "^\[options\]" "$conf"; then
      sudo sed -i '/^\[options\]/a IgnorePkg = libfprint libfprint-egismoc-sdcp-git' "$conf"
    fi
    warn "libfprint/libfprint-egismoc-sdcp-git are now excluded from 'omarchy update' and pacman upgrades."
    warn "You'll need to update this driver manually going forward — it won't happen automatically."
  fi
}

setup_pam_integration() {
  # Back up both files before touching them. This backup is also what the
  # global error trap (on_error) uses to auto-restore if anything below fails.
  mkdir -p "$PAM_BACKUP_DIR"
  [[ -f /etc/pam.d/sudo ]] && cp "/etc/pam.d/sudo" "$PAM_BACKUP_DIR/sudo"
  if [[ -f /etc/pam.d/polkit-1 ]]; then
    cp "/etc/pam.d/polkit-1" "$PAM_BACKUP_DIR/polkit-1"
  else
    touch "$PAM_BACKUP_DIR/.polkit-1-created"
  fi

  # Only wire in the laptop-closed clamshell gate if the binary actually
  # exists on this system — pam_exec pointed at a missing binary logs a
  # failure on every single auth attempt, even though [default=ignore]
  # keeps it from being fatal.
  # quiet_log is required in addition to quiet to suppress syslog/journald
  # level-3 errors when omarchy-hw-laptop-closed exits 1 (lid open).
  local fprintd_gate=""
  if command -v omarchy-hw-laptop-closed &>/dev/null; then
    fprintd_gate="auth      [success=1 default=ignore] pam_exec.so quiet quiet_log /usr/bin/omarchy-hw-laptop-closed"
  else
    warn "omarchy-hw-laptop-closed not found — skipping the clamshell gate in PAM (harmless on desktops)."
  fi

  # Upgrade existing clamshell gate to include quiet_log if configured without it
  local pam_file
  for pam_file in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
    if [[ -f "$pam_file" ]] && grep -q 'omarchy-hw-laptop-closed' "$pam_file" 2>/dev/null; then
      if ! grep -q 'quiet_log' "$pam_file" 2>/dev/null; then
        sudo sed -i 's/pam_exec\.so quiet \/usr\/bin\/omarchy-hw-laptop-closed/pam_exec.so quiet quiet_log \/usr\/bin\/omarchy-hw-laptop-closed/' "$pam_file"
        info "Upgraded $(basename "$pam_file") PAM clamshell gate with quiet_log."
      fi
    fi
  done

  # sudo: ensure pam_fprintd and clamshell gate are configured in correct sequence
  if ! grep -q pam_fprintd.so /etc/pam.d/sudo 2>/dev/null; then
    info "Configuring sudo for fingerprint authentication..."
    sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/sudo
  fi
  if [[ -n "$fprintd_gate" ]] && ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/sudo 2>/dev/null; then
    sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/sudo
  fi

  # polkit-1: ensure pam_fprintd and clamshell gate are configured in correct sequence
  if [[ -f /etc/pam.d/polkit-1 ]]; then
    if ! grep -q 'pam_fprintd.so' /etc/pam.d/polkit-1 2>/dev/null; then
      info "Configuring polkit for fingerprint authentication..."
      sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/polkit-1
    fi
    if [[ -n "$fprintd_gate" ]] && ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/polkit-1 2>/dev/null; then
      sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/polkit-1
    fi
  else
    sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
${fprintd_gate}
auth      sufficient pam_fprintd.so
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
  fi

  # Sanity check: a PAM edit should only ever grow these files (we insert
  # lines, never delete any). If either file came out shorter than its
  # backup, something went wrong — restore immediately rather than leaving
  # a possibly-broken auth stack in place.
  local orig_lines new_lines
  if [[ -f "$PAM_BACKUP_DIR/sudo" ]]; then
    orig_lines=$(wc -l < "$PAM_BACKUP_DIR/sudo")
    new_lines=$(wc -l < /etc/pam.d/sudo)
    if (( new_lines < orig_lines )); then
      warn "/etc/pam.d/sudo has fewer lines after edit than before edit — restoring backup as a precaution."
      restore_pam_backup
      fail "Aborting for safety. No PAM changes were left in place."
    fi
  fi
  if [[ -f "$PAM_BACKUP_DIR/polkit-1" ]]; then
    orig_lines=$(wc -l < "$PAM_BACKUP_DIR/polkit-1")
    new_lines=$(wc -l < /etc/pam.d/polkit-1)
    if (( new_lines < orig_lines )); then
      warn "/etc/pam.d/polkit-1 has fewer lines after edit than before edit — restoring backup as a precaution."
      restore_pam_backup
      fail "Aborting for safety. No PAM changes were left in place."
    fi
  fi

  # lock screen (Quickshell session lock):
  # timeout=-1 and max-tries=-1 prevent fprintd from timing out after 30s
  # and triggering an assertion crash loop in the SDCP driver when Quickshell re-arms.
  if [[ ! -f /etc/pam.d/omarchy-lock-fingerprint ]] || ! grep -q "timeout=-1" /etc/pam.d/omarchy-lock-fingerprint 2>/dev/null; then
    info "Configuring lock screen for persistent fingerprint authentication..."
    sudo tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so timeout=-1 max-tries=-1
account    include                     system-local-login
EOF
  fi
}

setup_egismoc_lock_plugin() {
  local current_user="${USER:-$(id -un)}"
  local user_lock_dir="$HOME/.config/omarchy/plugins/${current_user}.lock"
  local stock_lock_dir="/usr/share/omarchy/shell/plugins/lock"

  [[ -d "$stock_lock_dir" ]] || return 0

  info "Configuring EgisTec MOC lockscreen retry delay (1500ms)..."

  # 1. Ensure user-level cloned lock plugin exists
  if [[ ! -d "$user_lock_dir" ]]; then
    mkdir -p "$user_lock_dir"
    cp -aL "$stock_lock_dir/." "$user_lock_dir/"

    cat > "$user_lock_dir/manifest.json" <<EOF
{
  "schemaVersion": 1,
  "id": "${current_user}.lock",
  "name": "My Lock Screen",
  "version": "1.0.0",
  "author": "Omarchy",
  "description": "Quickshell session lock with separate password and fingerprint PAM flows.",
  "omarchy": {
    "capabilities": [
      "authentication"
    ],
    "clonedFrom": "omarchy.lock"
  },
  "kinds": [
    "service"
  ],
  "keepLoaded": true,
  "entryPoints": {
    "service": "Service.qml"
  }
}
EOF
    info "Cloned omarchy.lock to $user_lock_dir."
  fi

  # 2. Patch fingerprintRetryTimer interval to 1500ms in Service.qml
  # EgisTec MOC sensor needs ~1.5s to reset its USB endpoint and state machine
  # after a 60s idle timeout; 250ms causes assertion crash (self->task_ssm == NULL).
  if [[ -f "$user_lock_dir/Service.qml" ]]; then
    if ! grep -q "interval: 1500" "$user_lock_dir/Service.qml" 2>/dev/null; then
      sed -i '/id: fingerprintRetryTimer/,/repeat:/ s/interval: [0-9]\+/interval: 1500/' "$user_lock_dir/Service.qml"
      info "Patched fingerprintRetryTimer interval to 1500ms in $user_lock_dir/Service.qml."
    fi
  fi

  # 3. Ensure shell.json enables ${current_user}.lock and disables omarchy.lock
  activate_egismoc_lock_shell
}

activate_egismoc_lock_shell() {
  local current_user="${USER:-$(id -un)}"
  local shell_conf="$HOME/.config/omarchy/shell.json"

  if [[ -f "$shell_conf" ]] && command -v jq &>/dev/null; then
    local tmp_conf
    tmp_conf=$(mktemp)
    jq --arg id "${current_user}.lock" '
      .plugins = ((.plugins // []) | if any(.[]; .id == $id) then . else . + [{"id": $id}] end) |
      .disabledPlugins = ((.disabledPlugins // []) | if index("omarchy.lock") then . else . + ["omarchy.lock"] end) |
      .cloneSourceRestores = ((.cloneSourceRestores // []) | if index($id) then . else . + [$id] end)
    ' "$shell_conf" > "$tmp_conf" && mv "$tmp_conf" "$shell_conf"
    info "Activated ${current_user}.lock in $shell_conf."
  fi

  if command -v omarchy-shell &>/dev/null && OMARCHY_SHELL_IPC_TIMEOUT=1s omarchy-shell shell ping &>/dev/null; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

# Use Omarchy's own hardware detection rather than parsing lsusb manually.
if omarchy-hw-fingerprint; then
  info "Fingerprint sensor detected."

  # The SDCP driver is only needed for EgisTec Match-on-Chip sensors.
  # Stock libfprint works fine for Goodix, Synaptics, FPC, Elan, etc.
  # Check the USB bus for the specific EgisTec MOC vendor:product IDs.
  EGISMOC_IDS="1c7a:0582|1c7a:0583|1c7a:0584|1c7a:0586|1c7a:0587|1c7a:05a1|1c7a:05a5"

  if lsusb | grep -qE "$EGISMOC_IDS" || pacman -Q libfprint-egismoc-sdcp-git &>/dev/null; then
    HAS_EGISMOC=1
    info "EgisTec Match-on-Chip sensor detected — requires SDCP driver."

    if ! pacman -Q libfprint-egismoc-sdcp-git &>/dev/null; then
      echo
      warn "Stock libfprint lacks SDCP support for this sensor."
      warn "Fingerprint enrollments disappear after first verify without the patched driver."
      echo

      if confirm "Install libfprint-egismoc-sdcp-git from AUR? (replaces stock libfprint; a fresh build runs with --noconfirm, skipping PKGBUILD review)" true; then
        # Prefer a pre-compiled binary from the local dotfiles repo, user archive, or pacman cache.
        # This avoids the appstreamcli network-test failure during compilation.
        CACHED_PKG=$(find "$DOTFILES_DIR/packages" "$HOME/.local/share/packages" /var/cache/pacman/pkg \
          -name "libfprint-egismoc-sdcp-git-*.pkg.tar.zst" ! -name "*debug*" 2>/dev/null | head -n 1 || true)

        if [[ -n "$CACHED_PKG" ]]; then
          info "Found pre-compiled package: $CACHED_PKG"
          info "Package sha256: $(sha256sum "$CACHED_PKG" | awk '{print $1}')"
          # --ask=4 answers the "Remove libfprint?" conflict prompt with yes
          sudo pacman -U --noconfirm --ask=4 "$CACHED_PKG"
          archive_driver_pkg "$CACHED_PKG"
        else
          # Building from source touches the network (AUR + any deps) — check
          # reachability first instead of failing deep inside a yay build.
          if command -v omarchy-pkg-aur-accessible &>/dev/null && ! omarchy-pkg-aur-accessible; then
            fail "AUR is unreachable — cannot build libfprint-egismoc-sdcp-git. Check your network and re-run."
          fi
          command -v yay &>/dev/null || fail "yay is not installed — cannot build libfprint-egismoc-sdcp-git from AUR."

          info "Compiling from AUR (bypassing appstream network test)..."
          # Remove stock libfprint first (deps-only so fprintd stays if present)
          if pacman -Q libfprint &>/dev/null && ! pacman -Q libfprint-egismoc-sdcp-git &>/dev/null; then
            sudo pacman -Rdd --noconfirm libfprint
          fi
          yay -S --noconfirm --mflags="--nocheck" libfprint-egismoc-sdcp-git

          BUILT_PKG=$(find "$HOME/.cache/yay/libfprint-egismoc-sdcp-git" \
            -name "libfprint-egismoc-sdcp-git-*-x86_64.pkg.tar.zst" \
            ! -name "*debug*" 2>/dev/null | head -n 1 || true)
          archive_driver_pkg "$BUILT_PKG"
        fi

        lock_pacman_driver
      fi
    else
      info "EgisTec SDCP driver already installed."
      lock_pacman_driver
      # Ensure all offline recovery locations are populated
      CACHED_PKG=$(find "$DOTFILES_DIR/packages" "$HOME/.local/share/packages" /var/cache/pacman/pkg \
        -name "libfprint-egismoc-sdcp-git-*.pkg.tar.zst" ! -name "*debug*" 2>/dev/null | head -n 1 || true)
      archive_driver_pkg "$CACHED_PKG"
    fi
  fi

  # Install fprintd now that the proper libfprint provider is in place
  if omarchy-pkg-missing fprintd; then
    info "Installing fprintd..."
    omarchy-pkg-add fprintd
  fi
  sudo systemctl restart fprintd 2>/dev/null || true

  # Ensure PAM integration is configured (sudo, polkit, lock screen with clamshell gate)
  setup_pam_integration

  # Configure EgisTec MOC lockscreen retry delay (1500ms) to prevent USB timeout assertion crashes
  if (( HAS_EGISMOC )); then
    setup_egismoc_lock_plugin
  fi

  CURRENT_USER="${USER:-$(id -un)}"

  # On Match-on-Chip sensors, templates are stored in hardware NVRAM.
  # If root previously enrolled a finger (e.g. from running with sudo),
  # enrolling the same finger for the regular user will fail with enroll-duplicate.
  if sudo fprintd-list root 2>/dev/null | grep -q -E "^ +- #[0-9]+"; then
    echo
    warn "Enrolled fingerprint(s) found under user 'root' on Match-on-Chip sensor."
    warn "This will cause 'enroll-duplicate' errors when enrolling for '$CURRENT_USER'."
    if confirm "Remove root's enrolled fingerprint(s) so '$CURRENT_USER' can enroll?" true; then
      sudo fprintd-delete root || true
      info "Deleted root fingerprint enrollment."
    fi
  fi

  # Check if fingerprint enrollment is complete
  if command -v fprintd-list &>/dev/null &&
     fprintd-list "$CURRENT_USER" 2>/dev/null |
     grep -qE '^[[:space:]]*-[[:space:]]+#[0-9]+'; then
    info "Fingerprint already enrolled and PAM configured for $CURRENT_USER."
  else
    echo
    if (( ASSUME_YES )); then
      info "PAM configured. Run 'fprintd-enroll' after setup to enroll your finger."
    elif confirm "No fingerprint enrolled. Run fingerprint enrollment now?" true; then
      info "Swipe or place your right index finger repeatedly on the sensor until completed..."
      fprintd-enroll "$CURRENT_USER" || warn "Fingerprint enrollment did not complete."
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

  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    local item
    for item in "$src"/*; do
      [[ -e "$item" ]] || continue
      sync_item "$item" "$dest/$(basename "$item")"
    done
  else
    # Skip if file already exists and is identical
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest" 2>/dev/null; then
      return 0
    fi

    # Back up existing non-symlink file before overwriting
    if [[ -f "$dest" && ! -L "$dest" ]]; then
      mkdir -p "$(dirname "$BACKUP_DIR/${dest#$HOME/}")"
      cp -a "$dest" "$BACKUP_DIR/${dest#$HOME/}"
    fi

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

# Re-activate EgisTec MOC lockscreen plugin in shell.json if dotfiles deployment touched shell.json
if (( HAS_EGISMOC )); then
  activate_egismoc_lock_shell
fi

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
# Step 6: Reload Desktop Services
# ---------------------------------------------------------------------------
log "Step 6 · Reload Services"

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

# Clean up empty backup directories
if [[ -d "$PAM_BACKUP_DIR" ]] && [[ -z "$(ls -A "$PAM_BACKUP_DIR" 2>/dev/null)" ]]; then
  rmdir "$PAM_BACKUP_DIR" 2>/dev/null || true
fi
if [[ -d "$BACKUP_DIR" ]] && [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
  rmdir "$BACKUP_DIR" 2>/dev/null || true
elif [[ -d "$BACKUP_DIR" ]]; then
  info "Previous configs backed up to: $BACKUP_DIR"
fi

# Final sanity check: confirm sudo still works before you close this terminal.
# This is the single most important check after a PAM edit — if it fails,
# do NOT close this window; open a fresh root shell (or use the backup at
# $PAM_BACKUP_DIR) to fix /etc/pam.d/sudo before you lose your only sudo session.
if sudo -v 2>/dev/null; then
  info "sudo access confirmed working after setup."
else
  warn "Could not confirm sudo still works! Do NOT close this terminal."
  warn "Backups of the pre-edit PAM files are at: $PAM_BACKUP_DIR"
fi

log "Setup complete!"
