<div align="center">

# Omarchy Quattro Personal Dotfiles & Configurations

[![Platform](https://img.shields.io/badge/platform-Arch%20Linux-1793D1?logo=archlinux&logoColor=white)](https://archlinux.org)
[![Omarchy](https://img.shields.io/badge/omarchy-quattro-2b6cb0)](https://omarchy.org)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Maintained](https://img.shields.io/badge/maintained-yes-brightgreen)](#)

Personal Hyprland / Omarchy Quattro configuration and installer, structured for reproducible setup across machines.

</div>

---

## Contents

- [Overview](#overview)
- [Keybindings](#keybindings)
- [Audio Priority Rules](#audio-priority-rules)
- [Installation](#installation-on-another-omarchy-machine)
- [Safety Guards](#safety-guards)
- [Security & Update Safety](#security--omarchy-update-safety)
- [Documentation](#documentation-guides)
- [Devices in Use](#devices-in-use)

---

## Overview

| Component | Path | Highlights |
|---|---|---|
| Hyprland | `.config/hypr/` | Custom keybindings (`bindings.lua`), window rules for Android Emulator / QEMU (floating, full opacity), input & look'n'feel overrides |
| Omarchy Shell | `.config/omarchy/` *(optional)* | Bar/widget layout (`shell.json`), custom themes (`awsm-changi`, `luminous`, `sora-koi`), menu extensions (`omarchy-menu.jsonc`), theme-set automation hooks |
| Audio (WirePlumber) | `.config/wireplumber/`, `.local/share/wireplumber/` | Sink priority rules, dynamic hardware jack autoswitcher (`sof-autoswitch.lua`), Bluetooth A2DP autoconnect |
| Terminals & Shell Tools | various | Ghostty, Alacritty, Kitty, Foot configs; Starship, btop, lazygit, git config; `.bashrc` / `.zshrc` |

## Keybindings

| Binding | Action |
|---|---|
| `F7` / `SUPER + P` / `XF86Display` | Toggle `crmne.hyprmoncfg` display manager |
| `F8` / `SUPER + L` | Lock screen (`omarchy-system-lock`) |
| `ALT + SPACE` | Application launcher |
| `SUPER + SHIFT + S` | Screen capture |

## Audio Priority Rules

`50-alsa-output-priority.conf` sets WirePlumber 0.5 sink priorities:

| Output | Priority | Note |
|---|---|---|
| Headphones | `1500` | Highest — always preferred when connected |
| Internal Speakers | `1200` | Fallback default |
| HDMI Monitors | `600` | Deliberately low — prevents external displays from stealing audio |

---

## Installation on Another Omarchy Machine

### 1. Clone the repository

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
```

### 2. Run the installer

```bash
./install.sh        # interactive — prompts before AUR/optional steps
./install.sh -y      # unattended — accepts all defaults
```

### What `install.sh` does

| Step | Action |
|---|---|
| Pre-flight | Confirms this is an Omarchy install, warns if the detected version looks pre-Quattro, refuses to run a second instance concurrently, keeps `sudo` alive for the run |
| 1 | Installs official packages (`omarchy-zsh`, `zsh-autosuggestions`, `usbutils`) and Ghostty |
| 2 | Detects EgisTec Match-on-Chip fingerprint hardware, installs the SDCP driver (checksum-tracked), configures PAM for sudo / polkit / lock screen — automatically backed up beforehand and rolled back if anything fails |
| 3 | Prompts for optional AUR packages (`hyprmoncfg`, `brave-origin-bin`) |
| 4 | Backs up any conflicting existing configs, then deploys `.config` and `.local` files |
| 5 | Configures the native SSH agent via systemd socket activation |
| 6 | Reloads Hyprland, WirePlumber, and the Omarchy Shell; confirms `sudo` still works before exiting |

> [!NOTE]
> Earlier versions of this repo also installed a set of third-party Omarchy Shell plugins during setup. That step has been removed — plugin installation is no longer part of `install.sh`.

---

## Safety Guards

`install.sh` treats anything touching authentication or system packages as higher-risk than plain dotfile syncing, and guards accordingly:

| Guard | What it protects against |
|---|---|
| Lockfile (`~/.cache/omarchy-dotfiles-install.lock`) | Two copies of the installer running at once |
| `sudo` keep-alive | The `sudo` timestamp expiring mid-run and re-prompting unpredictably |
| PAM backup before edit | `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` are copied to `~/.dotfiles-backup/<timestamp>/pam/` before any edit |
| Auto-restore on failure | If any step fails after the PAM backup exists, both files are restored automatically |
| Line-count sanity check | PAM edits only ever insert lines; a file that comes out *shorter* than its backup triggers an immediate restore, not a silent continue |
| Checksum tracking for the cached fingerprint driver binary | A changed hash under the same filename is flagged, not silently trusted and overwritten |
| AUR reachability check | Network issues are caught before a `yay` build starts, not partway through |
| Final `sudo -v` check | The last thing the script does is confirm `sudo` still works, and tells you explicitly not to close the terminal if it doesn't |

---

## Security & Omarchy Update Safety

> [!IMPORTANT]
> This installer is **not** limited to `$HOME`. Step 2 (fingerprint setup) makes real changes outside your home directory:
> - Edits `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` to add fingerprint authentication
> - Writes `/etc/pam.d/omarchy-lock-fingerprint` for the session lock screen
> - May edit `/etc/pacman.conf` (`IgnorePkg`) to pin the fingerprint driver against updates
> - Installs a system package (`libfprint-egismoc-sdcp-git`) via `pacman -U`, replacing stock `libfprint`
>
> These changes are backed up automatically and rolled back on failure (see [Safety Guards](#safety-guards)), but they are genuine system-level edits — review Step 2 in [SETUP_AND_ARCHITECTURE.md](SETUP_AND_ARCHITECTURE.md) before running on a new machine, particularly one without EgisTec fingerprint hardware where this step should just no-op.

What *does* stay contained to your user account:

- Everything deployed in Step 4 lives strictly under `$HOME/.config/` and `$HOME/.local/`
- `omarchy update` will not overwrite anything this repo deploys under `.config`/`.local` — those are user files by Omarchy convention
- No secrets are committed: API tokens, credentials, and private keys are excluded and expected to live in standard local state paths (`~/.local/state/`)

---

## Documentation Guides

- [SETUP_AND_ARCHITECTURE.md](SETUP_AND_ARCHITECTURE.md) — complete setup architecture, package breakdown, EgisTec fingerprint configuration, and recovery instructions
- [SYSTEM_HEALTH_AND_AUTH_AUDIT.md](SYSTEM_HEALTH_AND_AUTH_AUDIT.md) — comprehensive system health inspection, PAM & fprintd architecture, journalctl analysis, and upstream comparison
- [SSH_SETUP_GUIDE.md](SSH_SETUP_GUIDE.md) — native Arch & Omarchy SSH key generation, systemd user socket activation, and session auto-load guide

---

## Devices in Use

| Device | Role |
|---|---|
| Acer SFG14-71 | Main work laptop |
| Realme Slimbook (headless) | Home PC |
