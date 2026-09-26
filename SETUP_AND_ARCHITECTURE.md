# Omarchy Quattro Setup & Architecture Guide

Complete reference for all system configurations, hardware integrations, dotfiles,
packages, and recovery workflows.

---

## Quick Start

```bash
cd ~/DistroScripts/omarchy-quattro-dotfiles
./install.sh        # Interactive (prompts for AUR/optional steps)
./install.sh -y     # Unattended (accepts all defaults)
```

---

## System Architecture

```mermaid
graph TD
  A["Hardware Layer"] --> B["EgisTec MOC Fingerprint<br/>1c7a:0584"]
  A --> C["Audio (WirePlumber 0.5)<br/>HP 1500 > SPK 1200 > HDMI 600"]
  D["Authentication Layer"] --> E["PAM: sudo + polkit + lock screen<br/>auth sufficient pam_fprintd.so<br/>+ clamshell gate"]
  D --> F["SSH Agent<br/>systemd ssh-agent.socket<br/>AddKeysToAgent yes"]
  G["Desktop Layer"] --> H["Hyprland Lua DSL<br/>F7 hyprmoncfg · F8 lock<br/>Super+Shift+S screenshot"]
  G --> I["Omarchy Shell Plugins<br/>screen-time · hyprmoncfg · bluetooth-audio"]
  G --> J["Terminals<br/>Ghostty (zsh) · Foot · Alacritty · Kitty"]
  G --> K["WirePlumber<br/>Audio priority rules<br/>SOF jack autoswitcher"]
```

---

## Package Inventory

### Official Omarchy Repository (`pkgs.omarchy.org`)

| Package | What It Bundles |
| :--- | :--- |
| **`omarchy-zsh`** | `zsh`, `starship`, `eza`, `zoxide`, `fzf`, `bat`, `fd`, `mise`, `zsh-syntax-highlighting` |

### Official Arch Repositories (`core` / `extra`)

| Package | Purpose |
| :--- | :--- |
| `zsh-autosuggestions` | Fish-like command suggestions for Zsh |
| `fprintd` | D-Bus daemon for fingerprint reader management |
| `usbutils` | Hardware discovery (`lsusb`) |
| `ghostty` | GPU-accelerated terminal (pre-installed on Omarchy) |
| `foot` | Lightweight Wayland terminal fallback (pre-installed) |
| `btop` | Resource monitor (pre-installed) |
| `lazygit` | Terminal Git TUI (pre-installed) |

### AUR Packages (Explicit User Confirmation Required)

| Package | Purpose | Install Notes |
| :--- | :--- | :--- |
| **`hyprmoncfg`** | Multi-monitor TUI & daemon | Required for <kbd>F7</kbd> display toggle |
| **`brave-origin-bin`** | Minimalist Brave browser | Installed via `omarchy install browser brave-origin` |

---

## Fingerprint: EgisTec MOC SDCP

### The Problem
Stock `libfprint` lacks the full **SDCP (Secure Device Connection Protocol)** handshake
for EgisTec Match-on-Chip sensors (`1c7a:0582`–`05a5`). Without it, the sensor's
cryptographic key desyncs and enrollments disappear after the first verification.

Omarchy's own *Setup > Security > Fingerprint* (`omarchy setup security fingerprint`)
installs `libfprint-git` from the Omarchy package repo. As of September 2026 that
package carries only FocalTech patches, and upstream's egismoc SDCP work
(libfprint MR !547) is still unmerged — so the stock wizard reinstates the broken
behavior on this laptop. **Don't run it here.**

### Applied Solution
Everything below is done by `bin/egismoc-fingerprint setup` (linked to
`~/.local/bin`), which the menu's *Setup > Security > Fingerprint* entry is
overridden to run. On any other sensor it hands off to Omarchy's wizard.

1. **Driver**: `libfprint-egismoc-sdcp-git`, built from this repo's own
   [pinned PKGBUILD](packages/libfprint-egismoc-sdcp/) (TenSeventy7's SDCP
   fork at commit `4d128d4`) — not from the AUR. The archived binary is
   preferred, and installed only if its sha256 matches `packages/.sha256sums`.
2. **Update Lock**: [`/etc/pacman.conf`](file:///etc/pacman.conf) —
   `IgnorePkg = libfprint libfprint-egismoc-sdcp-git`.
   Prevents `omarchy update`, `pacman -Syu`, and `yay -Sua` from overwriting.
3. **Offline Archive**: Pre-compiled `.pkg.tar.zst` in `packages/`,
   `/var/cache/pacman/pkg/` and `~/.local/share/packages/` for offline
   reinstallation.
4. **PAM Integration** (only after a print is enrolled *and* verified):
   `auth sufficient pam_fprintd.so` in sudo/polkit/lock, with Omarchy's
   clamshell gate (`omarchy-hw-laptop-closed`, plus `quiet_log`) that skips
   fingerprint when the lid is closed. The lock screen's PAM has no fprintd
   timeout, to avoid a driver assertion loop when it re-arms.
5. **Lock screen**: `omarchy plugin clone omarchy.lock` → `<user>.lock`, with the
   fingerprint retry raised from 250ms to 1500ms (the sensor needs it to reset).
6. **Health check**: the `post-update` and `post-boot` hooks run
   `egismoc-fingerprint check`, which raises a clickable notification if the
   driver has been replaced, and keeps the lock-screen copy current: if an
   Omarchy update changed the stock lock screen, the copy is removed, re-cloned
   from it and re-patched (never while the session is locked). A failed rebuild
   leaves Omarchy's stock lock screen active and is retried on the next check.

Check every piece at once with `egismoc-fingerprint status`.

> [!IMPORTANT]
> **Password fallback is always available.** If the sensor fails, times out,
> or the lid is shut, PAM drops straight to the password prompt.

### Recovery
```bash
# Reinstall from the archived binary (verify it first — must match packages/.sha256sums)
(cd packages && sha256sum -c .sha256sums)
sudo pacman -U packages/libfprint-egismoc-sdcp-git-*.pkg.tar.zst

# Or rebuild from the pinned recipe
(cd packages/libfprint-egismoc-sdcp && makepkg -si)

# Re-enroll fingerprint directly (avoids pacman conflicts with stock libfprint)
fprintd-enroll "$USER"
```

---

## SSH Agent: Arch-Native Architecture

Uses OpenSSH's built-in systemd socket activation — no third-party wrappers.

| Component | File | Purpose |
| :--- | :--- | :--- |
| **Daemon** | `systemctl --user enable --now ssh-agent.socket` | Socket-activated agent at `/run/user/1000/ssh-agent.socket` |
| **Session Env** | [`~/.config/environment.d/ssh-agent.conf`](file:///home/arun/.config/environment.d/ssh-agent.conf) | Systemd, uwsm, Hyprland, and GUI apps inherit `SSH_AUTH_SOCK` |
| **Shell Env** | [`~/.bashrc`](file:///home/arun/.bashrc) + [`~/.zshrc`](file:///home/arun/.zshrc) | `export SSH_AUTH_SOCK=...` for all terminal sessions |
| **Auto-Load** | [`~/.ssh/config`](file:///home/arun/.ssh/config) | `AddKeysToAgent yes` — passphrase once per login session |

### How It Works
1. First `git push` or `ssh` command → prompted for passphrase **once**.
2. OpenSSH adds the key to the systemd agent automatically.
3. Every subsequent terminal, tmux, or GUI app uses the key without prompting.
4. Key cleared on logout/reboot.

---

## Dotfiles Repository

Location: [`~/DistroScripts/omarchy-quattro-dotfiles`](file:///home/arun/DistroScripts/omarchy-quattro-dotfiles)

```
.
├── install.sh                     # This setup script (orchestrator)
├── bin/egismoc-fingerprint        # EgisTec fingerprint setup/status/check → ~/.local/bin
├── lib/ui.sh                      # Shared prompt/log/sudo helpers
├── packages/                      # Pinned driver PKGBUILD + checksum-verified binary
├── CLAUDE.md (AGENTS.md)          # Guide for coding agents
├── SETUP_AND_ARCHITECTURE.md      # This guide
├── .bashrc                        # SSH socket + Android SDK
├── .zshrc                         # Starship + eza aliases + zsh plugins
├── .config/
│   ├── ghostty/config             # command = /usr/bin/zsh, JetBrainsMono
│   ├── hypr/
│   │   ├── bindings.lua           # F7, F8, Super+Shift+S, Alt+Space
│   │   ├── hyprland.lua           # Emulator/QEMU window rules
│   │   └── input.lua, looknfeel.lua, monitors.lua, autostart.lua
│   ├── omarchy/
│   │   ├── shell.json             # Status bar layout & widgets
│   │   ├── hooks/theme-set        # Theme change automation
│   │   ├── hooks/{pre-refresh-pacman,post-update,post-boot}.d/  # Driver pin + health check
│   │   └── extensions/omarchy-menu.jsonc  # Routes Setup > Security > Fingerprint
│   ├── wireplumber/               # Audio sink priority rules
│   ├── starship.toml, btop/btop.conf, lazygit/config.yml
│   ├── git/config                 # Aliases, rerere, histogram diff
│   ├── alacritty/, foot/, kitty/
│   └── ...
└── .local/
    └── share/wireplumber/scripts/ # SOF jack autoswitcher
```

---

## install.sh: What Each Step Does

| Step | Action | Omarchy API Used |
| :--- | :--- | :--- |
| **1** | Install official packages (omarchy-zsh, zsh-autosuggestions, usbutils, restic, rclone); Ghostty as default terminal | `omarchy-pkg-add`, `omarchy-install-terminal`, `omarchy-default-terminal` |
| **2** | Back up existing configs to `~/.dotfiles-backup/`; deploy all dotfiles; link `egismoc-fingerprint` into `~/.local/bin` | File copy with backup |
| **3** | EgisTec sensor → `egismoc-fingerprint setup` (see above); other sensor → Omarchy's wizard; failure doesn't stop the install | `omarchy-hw-fingerprint`, `omarchy-setup-security-fingerprint`, `omarchy-plugin-clone` |
| **4** | Prompt for optional AUR packages (hyprmoncfg, brave-origin) | `omarchy-pkg-aur-add`, `omarchy-install-browser` |
| **5** | Enable systemd `ssh-agent.socket`; write `environment.d` config; configure `~/.ssh/config` | `systemctl --user` |
| **6** | Reload WirePlumber, Hyprland (report `configerrors`), terminals, Omarchy Shell | `hyprctl`, `omarchy-restart-terminal`, `omarchy-restart-shell` |

---

## Keybindings

| Key | Action | Command |
| :--- | :--- | :--- |
| <kbd>F7</kbd> / <kbd>Super</kbd>+<kbd>P</kbd> / <kbd>XF86Display</kbd> | Toggle hyprmoncfg display manager | `omarchy-shell shell toggle crmne.hyprmoncfg` |
| <kbd>F8</kbd> / <kbd>Super</kbd>+<kbd>L</kbd> | Lock screen | `omarchy-system-lock` |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> | Screenshot | `omarchy-capture-screenshot` |
| <kbd>Alt</kbd>+<kbd>Space</kbd> | Application launcher | `omarchy-menu toggle apps` |

---

## Update Safety

| Concern | Protection |
| :--- | :--- |
| `omarchy update` replaces fingerprint driver | `IgnorePkg` in pacman.conf blocks both `libfprint` and `libfprint-egismoc-sdcp-git` |
| Stock fingerprint wizard or a migration installs `libfprint-git` | The menu entry is overridden to `egismoc-fingerprint`; if the driver is replaced anyway, the `post-update`/`post-boot` hooks raise a clickable reinstall notification (`IgnorePkg` can't block an explicit `pacman -S`) |
| `omarchy refresh pacman` wipes pacman.conf | Native `pre-refresh-pacman.d` hook automatically re-locks `IgnorePkg` before `pacman -Syyuu` runs |
| `omarchy update` overwrites dotfiles | All configs live in `~/.config/` — Omarchy never touches user configs |
| Driver source disappears or changes upstream | Build is pinned to one commit, and a checksum-verified binary is archived in `packages/`, `~/.local/share/packages/` and `/var/cache/pacman/pkg/` |
| Sensor fails / locked out | PAM uses `sufficient` — password fallback always works |
| Docked with lid closed | Clamshell gate skips fingerprint, goes straight to password |

---

## Devices

| Device | Role |
| :--- | :--- |
| **Acer sfg14-71** | Main work laptop |
| **Headless Realme Slimbook** | At-home converted PC |
