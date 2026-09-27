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
- [How dotfiles are deployed](#how-dotfiles-are-deployed)
- [Tests](#tests)
- [Safety Guards](#safety-guards)
- [Security & Update Safety](#security--omarchy-update-safety)
- [Documentation](#documentation-guides)
- [Devices in Use](#devices-in-use)

---

## Overview

| Component | Path | Highlights |
|---|---|---|
| Hyprland | `.config/hypr/` | Custom keybindings (`bindings.lua`), window rules for Android Emulator / QEMU (`hyprland.lua`), keyboard/touchpad/gesture settings (`input.lua`), blur scoped to the Mirador overview (`looknfeel.lua`) |
| Omarchy Shell | `.config/omarchy/` | Bar/widget layout (`shell.json`), menu extensions (`omarchy-menu.jsonc`), hooks |
| Audio (WirePlumber) | `.config/wireplumber/`, `.local/share/wireplumber/` | Sink priority rules, headphone/speaker autoswitcher (`sof-autoswitch.lua`) |
| Shell & tools | various | Ghostty (zsh, font size), git identity and `gh` credentials, `.bashrc` / `.zshrc` |

Only files that differ from Omarchy's own defaults are tracked. Everything else stays Omarchy's, so its updates keep reaching you. To start customizing another file, copy it from `~/.config` into the same path here.

Not installed by `install.sh` (add them yourself on a new machine): the community bar widgets that `shell.json` places — `agx.screen-time`, `crmne.hyprmoncfg`, `harshith.system-monitor`, `ssupt.bluetooth-audio` (*Setup › Plugins › Add*); the [Mirador](https://github.com/sanjyay/Mirador) overview (`omarchy plugin add https://github.com/sanjyay/Mirador.git`), which the keybindings and gestures below call; and `omazed`, which the `theme-set` hook calls. `hyprmoncfg` itself is offered in Step 4.

## Keybindings

| Binding | Action |
|---|---|
| `F7` / `SUPER + P` / `XF86Display` | Toggle `crmne.hyprmoncfg` display manager |
| `F8` / `SUPER + L` | Lock screen (`omarchy-system-lock`) |
| `ALT + SPACE` | Application launcher |
| `SUPER + SHIFT + S` | Screen capture |
| `SUPER + TAB` / `SUPER + SHIFT + TAB` | Mirador workspace carousel (hold Super, release to switch); replaces next/previous workspace |
| `SUPER + GRAVE` | Mirador full overview |
| 3-finger swipe up / down | Open / close the Mirador overview (3-finger sideways still switches workspace) |

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
git clone https://github.com/dev-learner-supreme/omarchy-quattro-dotfiles ~/omarchy-quattro-dotfiles
cd ~/omarchy-quattro-dotfiles
```

Any folder works, but **leave the repo where you ran `install.sh`**: `~/.local/bin/egismoc-fingerprint`
is a symlink into it, and the update/boot hooks reach the fingerprint tool through that link. If the
repo moves, they skip silently — re-run `./install.sh` from the new location to repoint it.
Details in [SETUP_AND_ARCHITECTURE.md](SETUP_AND_ARCHITECTURE.md#the-repo-folder-must-stay-put).

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
| 2 | Deploys `.config` / `.local` (see [How dotfiles are deployed](#how-dotfiles-are-deployed)), links `egismoc-fingerprint` into `~/.local/bin` | hooks in `~/.config/omarchy/hooks/*.d`, menu extension |
| 3 | Fingerprint: EgisTec sensor → `egismoc-fingerprint setup`; any other sensor → Omarchy's own wizard. A failure here doesn't stop the rest | `omarchy-hw-fingerprint`, `omarchy setup security fingerprint`, `omarchy plugin clone` |
| 4 | Optional AUR packages (`hyprmoncfg`, Brave Origin) | `omarchy pkg aur add`, `omarchy install browser` |
| 5 | SSH agent via systemd socket activation | — |
| 6 | Reloads WirePlumber, Hyprland (and reports `hyprctl configerrors`), terminals, and the Omarchy shell | `omarchy restart terminal`, `omarchy restart shell` |

`shell.json` is special: its `plugins`, `disabledPlugins` and `cloneSourceRestores` keys record which plugins are switched on *on that machine* (the cloned lock screen, Mirador, …), so the repo leaves them out and every deploy keeps the machine's own values. Only the bar layout and idle settings are shared. This matters for safety too: the laptop's `disabledPlugins` switches off Omarchy's stock lock screen in favor of the fingerprint clone, which would leave a machine without that clone with no lock screen at all.

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
- **Lock screen** — a native `omarchy plugin clone omarchy.lock` with the retry delay raised to 1500ms (the sensor needs it to reset). A clone doesn't get Omarchy's lock-screen updates on its own, so after every update and at boot it's compared with Omarchy's current lock screen and rebuilt if Omarchy changed it (you get a notification). It's never swapped while the screen is locked, and if a rebuild fails you fall back to Omarchy's stock lock screen, not a broken one.

Like Omarchy's own setup, PAM is only edited after a print is enrolled *and* verified.

## Working on this repo with Claude Code

[`CLAUDE.md`](CLAUDE.md) (also `AGENTS.md`) gives coding agents the repo layout and the hard rules — above all, never run the stock fingerprint wizard or install `libfprint-git` on the laptop. On Omarchy it complements the built-in `omarchy` skill that Claude Code already loads for `~/.config` work.

### How dotfiles are deployed

Omarchy's own updates edit some of these files (for example `shell.json` and `hyprland.lua`), and so do apps like hyprmoncfg. So `install.sh` remembers what it last deployed (in `~/.local/state/omarchy-dotfiles/deployed`) and treats each file accordingly:

| On this machine the file is… | What happens |
|---|---|
| missing | Added |
| identical to the repo | Nothing |
| exactly what `install.sh` put there last time | Updated to the repo's version |
| Omarchy's untouched default (same as `/etc/skel`) | Replaced, with a backup |
| **changed since the last deploy** | **You're asked:** keep yours, use the repo's (yours is backed up), copy yours into the repo, or show the difference. With `-y` it keeps yours and lists it at the end. |
| deleted from the repo, unchanged here | Removed, with a backup |
| deleted from the repo, but changed here | Kept (you're asked without `-y`), and no longer managed |
| `shell.json` differing only in plugin state | Treated as identical; any deploy keeps this machine's plugin state (see Step 2 note above) |

Files that are symlinks are left alone.

On a fresh install, expect a question about `~/.config/git/config` on the first run: Omarchy's installer writes your name and email into it, so it no longer matches `/etc/skel`. Choosing *Keep mine* leaves it unmanaged (and it's asked again next run); *Use the repo's version* brings in the `gh` credential helper for GitHub.

---

## Tests

```bash
tests/run.sh            # everything, in throwaway sandboxes (~10s)
tests/run.sh dotfiles   # just the tests whose name contains "dotfiles"
```

The tests run `install.sh` and `egismoc-fingerprint` against a fake home folder, fake `/etc`, a fake USB sensor, and stand-in Omarchy/pacman/sudo commands, so they never touch the real system. GitHub runs them on every push, along with ShellCheck, a checksum check of the archived driver, and a parse check of the JSON configs ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

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
| PAM sanity checks | Apart from fingerprint lines, sudo/polkit must match their backups exactly, and must still reach `system-auth`/`pam_unix` (password fallback); either check failing triggers an immediate restore |
| No silent overwrites | A config file changed on this machine since the last deploy is never replaced without asking |
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
- `omarchy update` can still edit some of those files through its migrations. That's expected, and the next `install.sh` run asks before replacing any file it changed (see [How dotfiles are deployed](#how-dotfiles-are-deployed))
- No secrets are committed: API tokens, credentials, and private keys are excluded and expected to live in standard local state paths (`~/.local/state/`)

---

## Documentation Guides

- [Omarchy-Setup-Explained.pdf](Omarchy-Setup-Explained.pdf) — the whole repo explained in plain English (start here if you're not technical)
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
