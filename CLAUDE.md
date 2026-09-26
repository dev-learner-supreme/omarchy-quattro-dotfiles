# Omarchy Quattro dotfiles — agent guide

Personal Omarchy 4.x setup for an Acer Swift Go 14 (SFG14-71) and a headless home PC.
On Omarchy, the stock `omarchy` skill is already loaded for `~/.config` work; this
file adds the rules specific to this repo and this hardware.

## Layout

| Path | What it is |
|---|---|
| `install.sh` | Orchestrator. Idempotent; safe to re-run. |
| `bin/egismoc-fingerprint` | EgisTec fingerprint command, linked into `~/.local/bin` |
| `lib/ui.sh` | Shared prompt/log/sudo helpers, sourced by both scripts |
| `packages/libfprint-egismoc-sdcp/PKGBUILD` | Pinned SDCP driver recipe |
| `packages/*.pkg.tar.zst` + `.sha256sums` | Archived driver binary and its checksum |
| `.config/`, `.local/` | Deployed into `$HOME` by `install.sh` Step 2 (copied, with backups) |
| `.config/omarchy/hooks/` | `pre-refresh-pacman`, `post-update`, `post-boot` hooks |

Edit files **here**, then run `./install.sh` (or copy the one file) to deploy.
Editing `~/.config` directly works too, but the change is lost on the next deploy
unless it is copied back into this repo.

## Hard rules

- **Never run `omarchy setup security fingerprint` on the laptop, and never install
  `libfprint` or `libfprint-git`.** Omarchy's `libfprint-git` has no SDCP support for
  the EgisTec `1c7a:0584` sensor; installing it replaces the working driver and
  prints vanish after the first verify. Use `egismoc-fingerprint setup` (the
  menu's *Setup > Security > Fingerprint* is already routed to it).
- **PAM edits** (`/etc/pam.d/{sudo,polkit-1,omarchy-lock-fingerprint}`) go through
  `bin/egismoc-fingerprint` only. Fingerprint is always `sufficient`, never
  `required`, for sudo and polkit, and a password path must remain. After any
  PAM change, the user must confirm `sudo -k true` works in a *new* terminal
  before closing the old one.
- **Never modify `/usr/share/omarchy/`** — read it to learn how commands work.
- Don't run `install.sh` or `egismoc-fingerprint setup` yourself: they need the
  user at a terminal (sudo, and a finger on the sensor). Ask the user to run them.
  Read-only checks are fine: `egismoc-fingerprint status`.

## Updating the fingerprint driver

1. Pick a commit from TenSeventy7/libfprint-egismoc-sdcp; set `_pin_commit` and
   `pkgver` (`r<commit count>.<7-char hash>`) in the PKGBUILD.
2. The user builds and tests: `cd packages/libfprint-egismoc-sdcp && makepkg -si`,
   then `fprintd-verify`.
3. Copy the new `.pkg.tar.zst` into `packages/` and append its line to
   `packages/.sha256sums` (`sha256sum <file>`). `install.sh` refuses unlisted binaries.

When upstream libfprint merges SDCP for egismoc (MR !547) and Omarchy's
`libfprint-git` picks it up, this whole driver setup can go: switch the laptop to
`omarchy setup security fingerprint` and drop the pin, hooks and menu override.

## Conventions

- In scripts, call Omarchy's `omarchy-*` binaries directly (as Omarchy's own
  scripts do); in docs and messages to the user, use the `omarchy <group> <cmd>` form.
- Prefer an Omarchy command over hand-rolled logic: check `omarchy commands` first.
- Hooks run with Omarchy's sudo timestamp revoked, so any `sudo` in them prompts;
  keep hooks quiet and only escalate when something actually drifted.
- Bash style: `set -Eeuo pipefail`, helpers from `lib/ui.sh`, `confirm` for
  every system-changing prompt (`-y` takes each prompt's default).

## Checks before committing

```bash
bash -n install.sh bin/egismoc-fingerprint lib/ui.sh .config/omarchy/hooks/*/*.hook
shellcheck -x install.sh bin/egismoc-fingerprint
```
