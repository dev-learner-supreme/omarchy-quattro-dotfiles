# libfprint-egismoc-sdcp (pinned personal build)

Source recipe for the EgisTec Match-on-Chip fingerprint driver used on the
**Acer Swift Go 14 (SFG14-71)** — sensor `1c7a:0584` (LighTuning ETU905A88-E).

Stock `libfprint` lists this sensor but has no SDCP support, so enrollments
look successful and then vanish on the first verify. This builds
[TenSeventy7/libfprint-egismoc-sdcp](https://github.com/TenSeventy7/libfprint-egismoc-sdcp),
which adds SDCP, pinned to commit `4d128d4` — the commit where upstream finished
enabling `1c7a:0584`, and the same commit the archived binary in `../` was built from.

## How `install.sh` uses it

1. **Archived binary first.** If a `libfprint-egismoc-sdcp-git-*.pkg.tar.zst`
   listed in `../.sha256sums` is found (in `../`, `~/.local/share/packages/` or
   `/var/cache/pacman/pkg/`) *and its sha256 matches*, that is installed. No network needed.
2. **Build from this PKGBUILD otherwise.** Built in a temp dir (the repo tree
   stays clean), installed with `pacman -U`, which swaps out stock `libfprint`
   in one transaction, then archived and its checksum recorded.

It never pulls the AUR package, so nothing depends on a third-party AUR
maintainer and no unreviewed PKGBUILD runs with `--noconfirm`.

## Building by hand

```bash
cd packages/libfprint-egismoc-sdcp
makepkg -si
```

`prepare()` applies two small, documented fixes: it links OpenSSL into the
egismoc driver (upstream issues #10/#14/#15), and it runs the metainfo test
offline (upstream issue #8), so the full test suite passes without `--nocheck`.

## Updating the pin

1. Pick a commit from <https://github.com/TenSeventy7/libfprint-egismoc-sdcp/commits/master>.
2. Set `_pin_commit` to its full hash and `pkgver` to `r<commit count>.<7-char hash>`.
3. `makepkg -si`, confirm `fprintd-verify` still works, then add the new
   binary and its checksum to `../` and `../.sha256sums`.

The driver is held back by `IgnorePkg` in `/etc/pacman.conf` (kept in place by
the hooks in `.config/omarchy/hooks/`), so it only ever changes when you do this on purpose.

## Authentication wiring

PAM (sudo, polkit, the Quickshell lock screen) is configured by `install.sh`
Step 2, not by this package. See [SETUP_AND_ARCHITECTURE.md](../../SETUP_AND_ARCHITECTURE.md).
The password fallback always works: fingerprint is `sufficient`, never `required`,
for sudo and polkit.

## Caveat

The SDCP code is a community reimplementation that hasn't been reviewed upstream.
That's fine for convenience unlocks on a personal laptop, but don't treat it as
equivalent to a vendor-audited implementation.
