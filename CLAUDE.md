# Omarchy Quattro dotfiles — agent guide

Personal Omarchy 4.x setup for an Acer Swift Go 14 (SFG14-71) and a headless home PC.
On Omarchy, the stock `omarchy` skill is already loaded for `~/.config` work; this
file adds the rules specific to this repo and this hardware.

## Layout

| Path | What it is |
|---|---|
| `install.sh` | Orchestrator. Idempotent; safe to re-run. |
| `bin/egismoc-fingerprint` | EgisTec fingerprint command, symlinked into `~/.local/bin` (hooks and menu use the link) |
| `bin/drive-sync` | Google Drive ↔ `~/GoogleDrive` via `rclone bisync`, symlinked into `~/.local/bin`. Opt-in: linked by `install.sh`, but `setup` is never run automatically — it needs a Google Cloud OAuth client only the user can create (`GOOGLE_DRIVE_SYNC_GUIDE.md`). |
| `lib/ui.sh` | Shared prompt/log/sudo helpers, sourced by all `bin/` scripts |
| `lib/dotfiles.sh` | Dotfile deployment: drift check, removals, deploy state |
| `packages/libfprint-egismoc-sdcp/PKGBUILD` | Pinned SDCP driver recipe |
| `packages/*.pkg.tar.zst` + `.sha256sums` | Archived driver binary and its checksum |
| `.config/`, `.local/` | Copied into `$HOME` by `install.sh` Step 2 |
| `.config/omarchy/hooks/` | `pre-refresh-pacman`, `post-update`, `post-boot` hooks |
| `tests/` | Sandbox tests; `tests/run.sh` (CI runs it on every push) |

Only files that **differ from Omarchy's defaults** belong in `.config/`. Don't add
a file that's identical to Omarchy's (`/etc/skel/<path>` on the machine), and
suggest removing one that has drifted back to stock: tracked copies override
Omarchy's updates to that file.

`shell.json` tracks the layout only: `plugins`, `disabledPlugins` and `cloneSourceRestores`
are per-machine plugin state that `lib/dotfiles.sh` ignores when comparing and preserves when
deploying. Keep them out of the repo copy (`"plugins": []`), and never commit a
`disabledPlugins` that turns off `omarchy.lock`.

Edit files **here**, then run `./install.sh` to deploy. If a file in `~/.config`
changed since the last deploy (a hand edit, an Omarchy migration, an app),
`install.sh` asks before replacing it, and can copy it back into the repo.

## Hard rules

- **Never run `omarchy setup security fingerprint` on the laptop, and never install
  `libfprint` or `libfprint-git`.** Omarchy's `libfprint-git` has no SDCP support for
  the EgisTec `1c7a:0584` sensor; installing it replaces the working driver and
  prints vanish after the first verify. Use `egismoc-fingerprint setup` (the
  menu's *Setup > Security > Fingerprint* is already routed to it).
- **PAM edits** (`/etc/pam.d/{sudo,polkit-1,omarchy-lock-fingerprint}`) go through
  `bin/egismoc-fingerprint` only. Fingerprint is always `sufficient`, never
  `required`, for polkit and the lock screen, and a password path must remain.
  **Sudo is kept password-only on purpose** — a non-interactive `sudo` call
  (a script, a hook, an agent) still tries `pam_fprintd.so` first, and if it
  overlaps another fingerprint session it crashes `fprintd` via this driver's
  `egismoc_open` reentrancy assertion (upstream, unfixed:
  TenSeventy7/libfprint-egismoc-sdcp#13). `setup_pam()` actively strips
  fingerprint lines from `/etc/pam.d/sudo` if it finds them. After any PAM
  change, the user must confirm `sudo -k true` works in a *new* terminal
  before closing the old one.
- **Don't hand-edit `~/.config/omarchy/plugins/<user>.lock/`.** It's rebuilt from
  Omarchy's stock lock screen whenever that changes, and any file that differs
  from stock (other than the retry delay) marks it stale. Change the lock
  screen through `bin/egismoc-fingerprint` instead.
- **Never modify `/usr/share/omarchy/`** — read it to learn how commands work.
- **The repo's location is load-bearing.** `~/.local/bin/egismoc-fingerprint` and
  `~/.local/bin/drive-sync` both link into it, and the fingerprint hooks skip silently if that
  link dangles. Don't move, rename or delete the checkout; if the user does, they must re-run
  `./install.sh` from the new path. Anything committed under `bin/` or `lib/` goes live at the
  next hook run (or next `drive-sync sync`), without `install.sh`.
- Don't run `install.sh` or `egismoc-fingerprint setup` yourself: they need the
  user at a terminal (sudo, and a finger on the sensor). Ask the user to run them.
  Read-only checks are fine: `egismoc-fingerprint status`.
- `drive-sync setup` needs the user's own Google Cloud OAuth client and a browser login —
  don't attempt it non-interactively. `drive-sync status`/`logs` are read-only and fine.

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
shellcheck -x install.sh bin/egismoc-fingerprint bin/drive-sync lib/*.sh tests/*.sh tests/lib/*.sh \
  .config/omarchy/hooks/theme-set .config/omarchy/hooks/*/*.hook
tests/run.sh
```

Add or update a test in `tests/run.sh` for any behavior change. Tests run in a
sandbox with stubbed Omarchy/pacman/sudo commands (`tests/lib/sandbox.sh`), so
they are safe to run anywhere.
