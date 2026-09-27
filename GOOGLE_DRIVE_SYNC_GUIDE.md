# Google Drive as a native folder (`bin/drive-sync`)

`~/GoogleDrive` synced both ways with your Google Drive, as real local files —
not a virtual mount. `bin/drive-sync` wraps `rclone bisync` and a systemd
`--user` timer that runs a sync pass every 15 minutes.

**Why not GNOME's own Google Drive integration**: GNOME 50 (March 2026)
dropped it — its `libgdata` dependency had no maintainer for four years and
was archived upstream. Installing `gnome-online-accounts` on this machine
today gets you the post-removal version; the Google option simply isn't there.

**Why `bisync` and not `rclone mount`**: a mount is virtual — a file's bytes
are fetched from Drive the moment you open it, so a network hiccup or a laptop
just waking from sleep can make an open hang or a listing go stale. `bisync`
keeps real local files, synced on a timer; opening one never depends on the
network being up right that second.

**rclone itself**: MIT-licensed, 58k+ GitHub stars, actively maintained
(current release: September 2026), installed here from Arch's own signed
`extra` repository — not a third-party download.

## What you have to do — Google Cloud Console

rclone's own shared OAuth client is being retired during 2026, so every setup
now needs your own. Do this once, signed in as the Google account with your
Drive (the one with the AI Pro 5TB plan):

1. **Create a project.** [console.cloud.google.com](https://console.cloud.google.com/) →
   the project picker at the top → **New Project**. Any name (e.g. `personal-rclone`).
2. **Enable the Drive API.** Left menu → *APIs & Services* → *Library* →
   search "Google Drive API" → **Enable**.
3. **Configure the OAuth consent screen.** *APIs & Services* → *OAuth consent screen*:
   - User type: **External** (this is a personal account, not Workspace).
   - App name and your email where asked — anything recognizable.
   - Scopes: add `.../auth/drive` (full Drive access — search "drive" if the
     picker doesn't show the raw scope string).
   - Test users: add your own Google account. You need this even though you're
     about to publish the app (step 5) — testing needs it before that.
4. **Create the OAuth client.** *APIs & Services* → *Credentials* → **Create
   Credentials** → **OAuth client ID** → Application type **Desktop app** →
   name it → **Create**. You'll get a **Client ID** and **Client secret**.
5. **Publish the app.** *APIs & Services* → *OAuth consent screen* → *Audience*
   → **Publish App**. **Don't skip this.** An app left in "Testing" has its
   login expire every 7 days — the sync would work fine for a week, then
   silently stop until you re-authorize. Publishing removes that; you don't
   need Google's formal verification for a personal app only you use.
   You'll see a one-time **"Google hasn't verified this app"** screen the
   first time you authorize (next step) — that's expected for a personal app;
   click **Advanced** → **Go to \<your app name\> (unsafe)**. It's your own
   app, requesting access to your own account.

Keep the Client ID and Secret out of chat or anywhere else they'd be logged —
you'll type them directly into `rclone config` in your own terminal.

## Setup on this machine

```bash
rclone config
```
- `n` (new remote), name it exactly **`gdrive`** (the script expects that name)
- type: `drive` (Google Drive)
- paste your Client ID and Client secret from above
- scope: `1` (full access)
- root folder / service account: leave blank
- "Use auto config?" → yes if you have a browser here (you do); it opens one,
  you sign in and approve
- "Configure as team drive?" → no, unless you actually use a Shared Drive

**Before running `drive-sync setup`, check `bin/drive-sync-filters.txt`.** It
excludes developer build junk (`node_modules`, `.git`, `build/`, caches, …) and
this laptop's own migration/backup dumps (`fedora-backup`, `omarchy-backup`,
`linux_migration_backup`, `DistroScripts`) from what gets pulled down — the
first attempt at this, without it, started pulling down 1,600+ `node_modules`
directories from an old project backup. If your Drive has other large folders
you don't want mirrored locally (a personal backups folder, credential
folders, etc.), add them there first — `rclone size "gdrive:Some Folder"`
tells you how big one is before you decide.

Then:
```bash
drive-sync setup
```
This finds the `gdrive` remote, runs the one-time `--resync` baseline (compares
your local folder and Drive, establishes a starting point — deletes nothing on
either side), enables the 15-minute sync timer, and adds `~/GoogleDrive` to
Nautilus's sidebar.

**Changed the filters file later?** rclone hashes it and refuses to sync under
stale rules, so the very next unattended run will fail loudly (you'll get the
"sync failed" notification) rather than silently syncing under the old rules
or the new ones inconsistently. Fix it with:
```bash
rm ~/.local/state/drive-sync/resync-done
drive-sync setup
```

## Living with it

```bash
drive-sync status   # remote, folder, baseline, timer — all should say ok
drive-sync logs     # last sync's output
drive-sync logs -f  # follow it live
drive-sync sync     # run a sync pass right now, instead of waiting for the timer
```

A failed sync raises a notification (`omarchy-notification-send`) rather than
failing silently; click it, or run `drive-sync logs`, to see why.

**Conflicts** (a file changed on both sides between syncs) are never resolved
automatically — both versions are kept, one renamed with a `.conflict` suffix,
so you decide. **Deletes** are capped at 10% of files per run
(`--max-delete 10`); a run that would delete more than that aborts instead of
sweeping through, in case a mistaken `rm -rf` or a Drive outage looks like "the
whole folder disappeared."

Google Docs/Sheets/Slides aren't synced as files (`--drive-skip-gdocs`) — they
have no real byte content to compare, so they stay purely on the web, which is
where you'd edit them anyway.

## Uninstalling

```bash
systemctl --user disable --now drive-sync.timer
rm ~/.config/systemd/user/drive-sync.{service,timer}
rm -r ~/.local/state/drive-sync
# ~/GoogleDrive itself is left alone — it's your real files, not synced trash.
```
