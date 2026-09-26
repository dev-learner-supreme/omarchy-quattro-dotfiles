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
| Omarchy Shell | `.config/omarchy/` *(optional)* | Bar/widget layout (`shell.json`), menu extensions (`omarchy-menu.jsonc`), theme-set automation hooks |
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
./install.sh -y     # unattended — each prompt takes its default answer
```

### What `install.sh` does

It is an orchestrator: wherever Omarchy has a native command for a step, it calls that command, so the result matches what the Omarchy menu would do.

| Step | Action | Omarchy-native pieces |
|---|---|---|
| Pre-flight | Confirms Omarchy, warns if pre-Quattro, one run at a time, keeps `sudo` alive | `omarchy version` |
| 1 | Official packages; Ghostty installed and set as the default terminal | `omarchy pkg add`, `omarchy install terminal`, `omarchy default terminal` |
| 2 | Backs up conflicting configs, deploys `.config` / `.local`, links `egismoc-fingerprint` into `~/.local/bin` | hooks in `~/.config/omarchy/hooks/*.d`, menu extension |
| 3 | Fingerprint: EgisTec sensor → `egismoc-fingerprint setup`; any other sensor → Omarchy's own wizard. A failure here doesn't stop the rest | `omarchy-hw-fingerprint`, `omarchy setup security fingerprint`, `omarchy plugin clone` |
| 4 | Optional AUR packages (`hyprmoncfg`, Brave Origin) | `omarchy pkg aur add`, `omarchy install browser` |
| 5 | SSH agent via systemd socket activation | — |
| 6 | Reloads WirePlumber, Hyprland (and reports `hyprctl configerrors`), terminals, and the Omarchy shell | `omarchy restart terminal`, `omarchy restart shell` |

Dotfiles deploy *before* the fingerprint step on purpose: the tracked `shell.json` has an empty `plugins[]`, so deploying it after enabling the cloned lock screen would switch it back off.

## Fingerprint (EgisTec Match-on-Chip)

Omarchy's stock *Setup > Security > Fingerprint* installs `libfprint-git`, which has no SDCP support for EgisTec sensors like this laptop's `1c7a:0584` — prints vanish on the first verify. `bin/egismoc-fingerprint` is the replacement, and it defers to Omarchy's wizard on any other sensor:

```bash
egismoc-fingerprint setup     # driver, enrollment + verify, PAM, lock screen (re-runnable)
egismoc-fingerprint status    # read-only report of every piece
egismoc-fingerprint check     # what the hooks run: no sudo, notifies if the driver was replaced
```

It's wired into Omarchy in three places:

- **Menu** — `omarchy-menu.jsonc` overrides `setup.security.fingerprint`, so *Setup > Security > Fingerprint* runs this instead of the stock wizard.
- **Hooks** — `pre-refresh-pacman` keeps the driver in `IgnorePkg`; `post-update` repairs PAM drift; `post-update` and `post-boot` send a clickable *"Fingerprint driver replaced"* notification if anything swaps the driver out. All are no-ops on machines without the SDCP driver.
- **Lock screen** — a native `omarchy plugin clone omarchy.lock` with the retry delay raised to 1500ms (the sensor needs it to reset).

Like Omarchy's own setup, PAM is only edited after a print is enrolled *and* verified.

## Working on this repo with Claude Code

[`CLAUDE.md`](CLAUDE.md) (also `AGENTS.md`) gives coding agents the repo layout and the hard rules — above all, never run the stock fingerprint wizard or install `libfprint-git` on the laptop. On Omarchy it complements the built-in `omarchy` skill that Claude Code already loads for `~/.config` work.

---

## Safety Guards

Anything touching authentication or system packages is treated as higher-risk than plain dotfile syncing (the PAM and driver guards live in `bin/egismoc-fingerprint`):

| Guard | What it protects against |
|---|---|
| Lockfile (`~/.cache/omarchy-dotfiles-install.lock`) | Two copies of the installer running at once; a lock left by a killed run is detected by PID and cleared |
| `sudo` keep-alive | The `sudo` timestamp expiring mid-run; detached from stdout so `./install.sh \| tee log` doesn't hang at the end |
| Enroll before PAM | PAM is only touched once a print is enrolled and verified, so auth never points at a sensor that can't match |
| PAM backup before edit | `/etc/pam.d/sudo`, `polkit-1` and `omarchy-lock-fingerprint` are copied to `~/.dotfiles-backup/<timestamp>/pam/` before any edit |
| Scoped auto-restore | If the PAM edit fails or is interrupted (Ctrl-C), all three files are restored. A later, unrelated failure (e.g. Step 5) leaves a completed PAM setup alone |
| PAM sanity checks | Edits only ever insert lines, and sudo/polkit must still reach `system-auth`/`pam_unix` (password fallback); either check failing triggers an immediate restore |
| Checksum-verified driver install | A cached driver binary is installed only if its sha256 matches `packages/.sha256sums`; unlisted or tampered binaries are ignored with a warning |
| Pinned source build | With no verified binary, the driver is built from the repo's own pinned [PKGBUILD](packages/libfprint-egismoc-sdcp/) — never from the AUR — after a network check |
| Real PAM re-auth at the end | `sudo -k true` re-authenticates through the edited stack (fingerprint or password) without dropping the cached session; if it fails, you're offered a one-step restore |
| `-y` takes defaults | Unattended mode answers each prompt with its default, so default-No prompts stay No |

---

## Security & Omarchy Update Safety

> [!IMPORTANT]
> This installer is **not** limited to `$HOME`. Step 3 (fingerprint setup, on EgisTec hardware) makes real changes outside your home directory:
> - Edits `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` to add fingerprint authentication
> - Writes `/etc/pam.d/omarchy-lock-fingerprint` for the session lock screen
> - May edit `/etc/pacman.conf` (`IgnorePkg`) to pin the fingerprint driver against updates
> - Installs a system package (`libfprint-egismoc-sdcp-git`) via `pacman -U`, replacing stock `libfprint` — see [packages/libfprint-egismoc-sdcp/](packages/libfprint-egismoc-sdcp/) for the pinned recipe
>
> These changes are backed up automatically and rolled back on failure (see [Safety Guards](#safety-guards)), but they are genuine system-level edits. On a machine without an EgisTec sensor this step makes none of them: it defers to Omarchy's own wizard, or skips.

What *does* stay contained to your user account:

- Everything deployed in Step 2 lives strictly under `$HOME/.config/` and `$HOME/.local/`
- `omarchy update` will not overwrite anything this repo deploys under `.config`/`.local` — those are user files by Omarchy convention
- No secrets are committed: API tokens, credentials, and private keys are excluded and expected to live in standard local state paths (`~/.local/state/`)

---

## Documentation Guides

- [CLAUDE.md](CLAUDE.md) — guide for coding agents (Claude Code, Codex via `AGENTS.md`)
- [packages/libfprint-egismoc-sdcp/](packages/libfprint-egismoc-sdcp/) — the pinned driver recipe and how to bump it
- [SETUP_AND_ARCHITECTURE.md](SETUP_AND_ARCHITECTURE.md) — complete setup architecture, package breakdown, EgisTec fingerprint configuration, and recovery instructions
- [SYSTEM_HEALTH_AND_AUTH_AUDIT.md](SYSTEM_HEALTH_AND_AUTH_AUDIT.md) — comprehensive system health inspection, PAM & fprintd architecture, journalctl analysis, and upstream comparison
- [SSH_SETUP_GUIDE.md](SSH_SETUP_GUIDE.md) — native Arch & Omarchy SSH key generation, systemd user socket activation, and session auto-load guide

---

## Devices in Use

| Device | Role |
|---|---|
| Acer SFG14-71 | Main work laptop |
| Realme Slimbook (headless) | Home PC |
