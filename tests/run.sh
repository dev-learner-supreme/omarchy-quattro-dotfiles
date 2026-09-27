#!/usr/bin/env bash
# Runs every test in a fresh sandbox (see tests/lib/sandbox.sh).
# Usage: tests/run.sh [substring-of-test-name]
set -uo pipefail

# shellcheck source=tests/lib/sandbox.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/sandbox.sh"
trap sb_cleanup EXIT

PASSED=0
FAILED=0
FAILURES=()
CURRENT=""

check() {
  local what="$1"; shift
  if "$@"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    FAILURES+=("$CURRENT: $what")
    echo "    FAIL: $what"
  fi
}
has()   { grep -qE -- "$2" "$1" 2>/dev/null; }
lacks() { ! grep -qE -- "$2" "$1" 2>/dev/null; }
count() { [[ "$(grep -cE -- "$2" "$1" 2>/dev/null)" == "$3" ]]; }
same()  { cmp -s "$1" "$2"; }
exists() { [[ -e "$1" ]]; }
absent() { [[ ! -e "$1" ]]; }

backup_folders() { find "$SB/home/.dotfiles-backup" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l; }
FP() { echo "$SB/repo/bin/egismoc-fingerprint"; }
CLONE() { echo "$SB/home/.config/omarchy/plugins/arun.lock"; }
STOCK_LOCK() { echo "$SB/omarchy/shell/plugins/lock"; }

# A laptop with the EgisTec sensor, one print enrolled, after `install.sh -y`.
installed_laptop() {
  sb_fresh
  echo 1 > "$SB/state/prints"
  sb_run bash "$SB/repo/install.sh" -y > "$SB/install.log" 2>&1
}

# ------------------------------------------------------------------------------
# Fingerprint and PAM
# ------------------------------------------------------------------------------

test_unattended_install_on_egistec_laptop() {
  installed_laptop
  local rc=$?
  check "install exits 0" test "$rc" -eq 0
  check "SDCP driver installed from the verified archive" has "$SB/state/installed" '^libfprint-egismoc-sdcp-git$'
  check "sudo: fingerprint, then password" has "$SB/etc/pam.d/sudo" 'sufficient pam_fprintd'
  check "sudo: lid gate with quiet_log" has "$SB/etc/pam.d/sudo" 'quiet quiet_log /usr/bin/omarchy-hw-laptop-closed'
  check "sudo: fingerprint lines after the header" has <(head -1 "$SB/etc/pam.d/sudo") '^#%PAM'
  check "sudo: password path kept" has "$SB/etc/pam.d/sudo" 'include[[:space:]]+system-auth'
  check "polkit built from the vendor copy" has "$SB/etc/pam.d/polkit-1" 'password +include +system-auth'
  check "lock screen PAM has no timeout" has "$SB/etc/pam.d/omarchy-lock-fingerprint" 'timeout=-1 max-tries=-1'
  check "driver pinned in IgnorePkg" has "$SB/etc/pacman.conf" '^IgnorePkg.*libfprint-egismoc-sdcp-git'
  check "lock screen cloned and patched" has "$(CLONE)/Service.qml" 'interval: 1500'
  check "fingerprint command linked" test -L "$SB/home/.local/bin/egismoc-fingerprint"
  check "dotfiles deployed" exists "$SB/home/.config/hypr/bindings.lua"
  sb_run "$(FP)" status > "$SB/status.log" 2>&1
  check "status reports everything ok" lacks "$SB/status.log" '\[!!\]'
}

test_rerun_changes_nothing() {
  installed_laptop
  cp -a "$SB/etc/pam.d" "$SB/pam-before"
  cp -a "$SB/home/.dotfiles-backup" "$SB/backups-before"
  local backups_before
  backups_before="$(backup_folders)"
  sb_run bash "$SB/repo/install.sh" -y > "$SB/rerun.log" 2>&1
  check "PAM files unchanged" diff -r "$SB/pam-before" "$SB/etc/pam.d"
  check "still exactly one IgnorePkg line" count "$SB/etc/pacman.conf" '^IgnorePkg' 1
  check "no dotfile touched" lacks "$SB/rerun.log" 'Added:|Updated:|Replaced|Removed'
  check "no new backup folder" test "$(backup_folders)" -eq "$backups_before"
  check "first run's backups intact" diff -r "$SB/backups-before" "$SB/home/.dotfiles-backup"
}

test_other_sensor_uses_omarchy_wizard() {
  sb_fresh 27c6:6594
  sed -i '/^fprintd$/d' "$SB/state/installed"
  sb_run bash "$SB/repo/install.sh" -y > "$SB/install.log" 2>&1
  check "points at Omarchy's wizard" has "$SB/install.log" 'omarchy setup security fingerprint'
  check "detect says no" test "$(sb_run "$(FP)" detect > /dev/null; echo $?)" -eq 1
  sb_run "$(FP)" setup > /dev/null 2>&1
  check "setup hands off to Omarchy" has "$SB/state/calls" '^omarchy-setup-security-fingerprint$'
  cp "$SB/etc/pacman.conf" "$SB/pacman.before"
  sb_run bash "$SB/home/.config/omarchy/hooks/post-update.d/lock-driver.hook"
  sb_run bash "$SB/home/.config/omarchy/hooks/pre-refresh-pacman.d/lock-driver.hook"
  check "hooks leave pacman.conf alone" same "$SB/pacman.before" "$SB/etc/pacman.conf"
}

test_tampered_driver_is_refused() {
  sb_fresh
  echo 1 > "$SB/state/prints"
  cp "$SB/etc/pam.d/sudo" "$SB/sudo.orig"
  echo tampered >> "$SB"/repo/packages/libfprint-egismoc-sdcp-git-*.pkg.tar.zst
  sb_run bash "$SB/repo/install.sh" -y > "$SB/install.log" 2>&1
  check "mismatch reported" has "$SB/install.log" 'CHECKSUM MISMATCH'
  check "driver not installed" lacks "$SB/state/installed" 'egismoc'
  check "PAM untouched" same "$SB/sudo.orig" "$SB/etc/pam.d/sudo"
  check "rest of the install still ran" has "$SB/install.log" 'Setup complete'
}

test_pam_edit_that_changes_other_lines_is_rolled_back() {
  sb_fresh
  echo 1 > "$SB/state/prints"
  cp "$SB/etc/pam.d/sudo" "$SB/sudo.orig"
  sb_run env CORRUPT_SUDO=1 bash "$SB/repo/install.sh" -y > "$SB/install.log" 2>&1
  check "detected" has "$SB/install.log" 'changed beyond its fingerprint lines'
  check "sudo restored exactly" same "$SB/sudo.orig" "$SB/etc/pam.d/sudo"
}

test_failed_pam_write_is_rolled_back() {
  sb_fresh
  echo 1 > "$SB/state/prints"
  cp "$SB/etc/pam.d/sudo" "$SB/sudo.orig"
  sb_run env FAIL_ON_POLKIT_WRITE=1 bash "$SB/repo/install.sh" -y > "$SB/install.log" 2>&1
  check "rollback ran" has "$SB/install.log" 'restoring pre-edit PAM files'
  check "sudo restored exactly" same "$SB/sudo.orig" "$SB/etc/pam.d/sudo"
  check "polkit file it created is removed" absent "$SB/etc/pam.d/polkit-1"
  check "rest of the install still ran" has "$SB/install.log" 'Setup complete'
}

test_interactive_first_setup_enrolls_then_wires_pam() {
  sb_fresh
  printf '\n' | sb_run_tty "$(FP)" setup > "$SB/setup.log" 2>&1
  check "finger enrolled" test "$(cat "$SB/state/prints")" -eq 1
  check "verified before PAM" has "$SB/setup.log" 'verify-match'
  check "sudo re-checked through the new stack" has "$SB/setup.log" 'sudo works with fingerprint'
  check "sudo has fingerprint" has "$SB/etc/pam.d/sudo" 'pam_fprintd'
}

test_failed_sudo_recheck_offers_restore() {
  sb_fresh
  cp "$SB/etc/pam.d/sudo" "$SB/sudo.orig"
  printf '\ny\n' | sb_run_tty env SUDO_REAUTH_FAIL=1 bash -c "$(FP) setup; echo EXIT=\$?" > "$SB/setup.log" 2>&1
  check "sudo restored" same "$SB/sudo.orig" "$SB/etc/pam.d/sudo"
  check "setup reports failure" has "$SB/setup.log" 'EXIT=1'
}

test_replaced_driver_raises_notification() {
  installed_laptop
  sed -i 's/^libfprint-egismoc-sdcp-git$/libfprint-git/' "$SB/state/installed"
  : > "$SB/state/calls"
  sb_run bash "$SB/home/.config/omarchy/hooks/post-boot.d/egismoc-check.hook"
  check "notifies" has "$SB/state/calls" 'Fingerprint driver replaced'
  check "click reinstalls" has "$SB/state/calls" 'egismoc-fingerprint\] \[setup\]'
}

# ------------------------------------------------------------------------------
# Lock-screen copy kept in step with Omarchy
# ------------------------------------------------------------------------------

test_lock_copy_rebuilt_after_omarchy_update() {
  installed_laptop
  echo "// upstream fix" >> "$(STOCK_LOCK)/LockView.qml"
  sb_run "$(FP)" status > "$SB/status.log" 2>&1
  check "status notices the copy is stale" has "$SB/status.log" 'older than Omarchy'
  : > "$SB/state/calls"
  sb_run bash "$SB/home/.config/omarchy/hooks/post-update.d/lock-driver.hook"
  check "rebuilt" has "$SB/state/calls" '^omarchy-plugin-clone'
  check "user told" has "$SB/state/calls" 'Lock screen updated'
  check "copy has Omarchy's change" has "$(CLONE)/LockView.qml" 'upstream fix'
  check "copy keeps the retry fix" has "$(CLONE)/Service.qml" 'interval: 1500'
}

test_lock_copy_left_alone_while_locked() {
  installed_laptop
  echo "// upstream fix" >> "$(STOCK_LOCK)/LockView.qml"
  : > "$SB/state/calls"
  sb_run env SESSION_LOCKED=1 "$(FP)" check
  check "nothing removed or cloned" lacks "$SB/state/calls" 'plugin-(remove|clone)'
  check "copy still there" exists "$(CLONE)/Service.qml"
}

test_failed_lock_rebuild_recovers_next_time() {
  installed_laptop
  echo "// upstream fix" >> "$(STOCK_LOCK)/LockView.qml"
  : > "$SB/state/calls"
  sb_run env FAIL_CLONE=1 "$(FP)" check
  check "critical notification" has "$SB/state/calls" 'Lock screen refresh failed'
  sb_run "$(FP)" check
  check "next check rebuilds it" has "$(CLONE)/Service.qml" 'interval: 1500'
}

test_renamed_retry_timer_is_reported() {
  installed_laptop
  sed -i 's/id: fingerprintRetryTimer/id: fingerprintRestartTimer/' "$(STOCK_LOCK)/Service.qml"
  : > "$SB/state/calls"
  sb_run "$(FP)" check
  check "notified that the fix no longer fits" has "$SB/state/calls" 'fingerprint fix not applied'
}

# ------------------------------------------------------------------------------
# Google Drive sync (bin/drive-sync)
# ------------------------------------------------------------------------------

DS() { echo "$SB/repo/bin/drive-sync"; }
REMOTES() { echo "$SB/state/rclone-remotes"; }
RESYNC_MARKER() { echo "$SB/home/.local/state/drive-sync/resync-done"; }

# A machine with the "gdrive" remote already configured and the baseline run.
drive_sync_ready() {
  sb_fresh
  printf 'y\ny\n' | sb_run_tty "$(DS)" setup > "$SB/drive-sync-setup.log" 2>&1
}

test_drive_sync_setup_unattended_without_remote_fails_with_guidance() {
  sb_fresh
  sb_run env NO_RCLONE_CONFIG=1 "$(DS)" setup -y > "$SB/log" 2>&1
  local rc=$?
  check "exits non-zero" test "$rc" -ne 0
  check "tells the user to run rclone config" has "$SB/log" "rclone config"
  check "no remote created" absent "$(REMOTES)"
  check "no baseline run" absent "$(RESYNC_MARKER)"
}

test_drive_sync_setup_interactive_creates_remote_and_baseline() {
  drive_sync_ready
  check "remote created" has "$(REMOTES)" '^gdrive:$'
  check "baseline recorded" exists "$(RESYNC_MARKER)"
  check "resync ran" has "$SB/state/calls" 'rclone bisync .*--resync'
  check "timer enabled" has "$SB/state/calls" 'systemctl --user enable --now drive-sync.timer'
  check "service unit written" has "$SB/home/.config/systemd/user/drive-sync.service" 'ExecStart=.*drive-sync sync'
  check "timer unit written" has "$SB/home/.config/systemd/user/drive-sync.timer" 'OnUnitActiveSec=15min'
  check "added to Nautilus bookmarks" has "$SB/home/.config/gtk-3.0/bookmarks" 'Google Drive'
}

test_drive_sync_setup_is_rerunnable_without_repeating_resync() {
  drive_sync_ready
  : > "$SB/state/calls"
  printf 'y\ny\n' | sb_run_tty "$(DS)" setup > "$SB/log2" 2>&1
  check "baseline not repeated" lacks "$SB/state/calls" 'rclone bisync .*--resync'
  check "said so" has "$SB/log2" "leaving it alone"
}

test_drive_sync_sync_is_a_noop_before_setup() {
  sb_fresh
  sb_run "$(DS)" sync
  check "no bisync attempted" lacks "$SB/state/calls" 'rclone bisync'
}

test_drive_sync_sync_is_a_noop_with_remote_but_no_baseline() {
  sb_fresh
  echo "gdrive:" > "$(REMOTES)"
  sb_run "$(DS)" sync
  check "no bisync attempted" lacks "$SB/state/calls" 'rclone bisync'
}

test_drive_sync_sync_runs_a_safe_recurring_bisync() {
  drive_sync_ready
  : > "$SB/state/calls"
  sb_run "$(DS)" sync
  check "recurring sync ran" has "$SB/state/calls" 'rclone bisync'
  check "no --resync on a normal run" lacks "$SB/state/calls" 'rclone bisync .*--resync'
  check "conflicts kept, never silently resolved" has "$SB/state/calls" 'conflict-resolve none'
  check "safe to run unattended" has "$SB/state/calls" 'resilient'
  check "delete safety guard set" has "$SB/state/calls" 'max-delete 10'
  check "filters file applied" has "$SB/state/calls" 'filters-file .*drive-sync-filters.txt'
}

test_drive_sync_filters_exclude_dev_junk_and_this_machines_backups() {
  sb_fresh
  local f="$SB/repo/bin/drive-sync-filters.txt"
  check "filters file exists" exists "$f"
  check "node_modules excluded at any depth" has "$f" '^- node_modules/\*\*$'
  check "git internals excluded" has "$f" '^- \.git/\*\*$'
  check "this machine's fedora backup excluded" has "$f" '^- /fedora-backup/\*\*$'
  check "this machine's omarchy backup excluded" has "$f" '^- /omarchy-backup/\*\*$'
}

test_drive_sync_sync_failure_raises_a_notification() {
  drive_sync_ready
  : > "$SB/state/calls"
  sb_run env FAIL_BISYNC=1 "$(DS)" sync > "$SB/log" 2>&1
  local rc=$?
  check "exits non-zero" test "$rc" -ne 0
  check "notifies" has "$SB/state/calls" 'Google Drive sync failed'
}

test_drive_sync_status_reports_missing_pieces_on_a_fresh_machine() {
  sb_fresh
  sb_run "$(DS)" status > "$SB/log" 2>&1
  check "flags the missing remote" has "$SB/log" 'no .gdrive. remote'
  check "flags the missing baseline" has "$SB/log" 'not run yet'
}

test_drive_sync_status_reports_ok_once_set_up() {
  drive_sync_ready
  sb_run "$(DS)" status > "$SB/log" 2>&1
  check "no failures reported" lacks "$SB/log" '\[!!\]'
}

# ------------------------------------------------------------------------------
# Dotfile deployment (lib/dotfiles.sh, run directly)
# ------------------------------------------------------------------------------

# A tiny repo with two managed files; the Omarchy default for a.conf is in skel.
dotfiles_env() {
  sb_fresh
  export DT="$SB/dt"
  mkdir -p "$DT"/{repo/.config/app,home/.config/app,skel/.config/app}
  echo "stock a" > "$DT/skel/.config/app/a.conf"
  echo "mine a"  > "$DT/repo/.config/app/a.conf"
  echo "mine b"  > "$DT/repo/.config/app/b.conf"
  cat > "$DT/deploy.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
ASSUME_YES=\${ASSUME_YES:-0}
DOTFILES_DIR="$DT/repo" BACKUP_DIR="$DT/backup"
source "$SB/repo/lib/ui.sh"
source "$SB/repo/lib/dotfiles.sh"
dotfiles_deploy
EOF
  chmod +x "$DT/deploy.sh"
}
deploy()     { sb_run env HOME="$DT/home" OMARCHY_SKEL="$DT/skel" ASSUME_YES=1 "$DT/deploy.sh"; }
deploy_tty() { sb_run_tty env HOME="$DT/home" OMARCHY_SKEL="$DT/skel" "$DT/deploy.sh"; }
state()      { echo "$DT/home/.local/state/omarchy-dotfiles/deployed"; }

test_dotfiles_fresh_machine() {
  dotfiles_env
  cp "$DT/skel/.config/app/a.conf" "$DT/home/.config/app/a.conf"
  deploy > "$DT/log" 2>&1
  check "Omarchy default replaced" same "$DT/repo/.config/app/a.conf" "$DT/home/.config/app/a.conf"
  check "default backed up" has "$DT/backup/.config/app/a.conf" 'stock a'
  check "missing file added" same "$DT/repo/.config/app/b.conf" "$DT/home/.config/app/b.conf"
  check "both recorded" count "$(state)" '\.config/app/[ab]\.conf' 2
}

test_dotfiles_repo_update_applied_without_asking() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "mine a v2" > "$DT/repo/.config/app/a.conf"
  deploy > "$DT/log" 2>&1
  check "updated" has "$DT/home/.config/app/a.conf" 'v2'
  check "said so" has "$DT/log" 'Updated: ~/.config/app/a.conf'
}

test_dotfiles_local_change_kept_when_unattended() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "changed by an Omarchy migration" > "$DT/home/.config/app/a.conf"
  echo "mine a v2" > "$DT/repo/.config/app/a.conf"
  deploy > "$DT/log" 2>&1
  check "local change kept" has "$DT/home/.config/app/a.conf" 'migration'
  check "reported" has "$DT/log" 'Kept your version'
  deploy > "$DT/log2" 2>&1
  check "asked again next run" has "$DT/log2" 'Kept your version'
}

test_dotfiles_local_change_replaced_on_request() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "local edit" > "$DT/home/.config/app/a.conf"
  printf 'r\n' | deploy_tty > "$DT/log" 2>&1
  check "repo version installed" same "$DT/repo/.config/app/a.conf" "$DT/home/.config/app/a.conf"
  check "local edit backed up" has "$DT/backup/.config/app/a.conf" 'local edit'
}

test_dotfiles_local_change_copied_into_repo() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "local edit" > "$DT/home/.config/app/a.conf"
  printf 'i\n' | deploy_tty > "$DT/log" 2>&1
  check "repo now has the local edit" has "$DT/repo/.config/app/a.conf" 'local edit'
  deploy > "$DT/log2" 2>&1
  check "no more questions" lacks "$DT/log2" 'changed on this machine'
}

test_dotfiles_show_difference_then_keep() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "local edit" > "$DT/home/.config/app/a.conf"
  printf 'd\nk\n' | deploy_tty > "$DT/log" 2>&1
  check "diff shown" has "$DT/log" '^\+local edit'
  check "kept" has "$DT/home/.config/app/a.conf" 'local edit'
}

test_dotfiles_deleted_from_repo_is_removed() {
  dotfiles_env
  deploy > /dev/null 2>&1
  rm "$DT/repo/.config/app/b.conf"
  deploy > "$DT/log" 2>&1
  check "removed" absent "$DT/home/.config/app/b.conf"
  check "backed up" has "$DT/backup/.config/app/b.conf" 'mine b'
  check "no longer recorded" lacks "$(state)" 'b\.conf'
}

test_dotfiles_deleted_but_changed_is_kept() {
  dotfiles_env
  deploy > /dev/null 2>&1
  echo "local edit" > "$DT/home/.config/app/b.conf"
  rm "$DT/repo/.config/app/b.conf"
  deploy > "$DT/log" 2>&1
  check "kept" has "$DT/home/.config/app/b.conf" 'local edit'
  check "no longer managed" lacks "$(state)" 'b\.conf'
}

test_dotfiles_symlink_left_alone() {
  dotfiles_env
  echo "elsewhere" > "$DT/elsewhere"
  ln -s "$DT/elsewhere" "$DT/home/.config/app/a.conf"
  deploy > "$DT/log" 2>&1
  check "link untouched" test -L "$DT/home/.config/app/a.conf"
  check "target untouched" has "$DT/elsewhere" 'elsewhere'
}

# shell.json: the repo tracks the layout; plugin state stays per machine.
shell_json_env() {
  dotfiles_env
  mkdir -p "$DT"/{repo,home,skel}/.config/omarchy
  echo '{"version":1,"bar":{"position":"top"},"plugins":[]}' > "$DT/repo/.config/omarchy/shell.json"
  echo '{"version":1,"bar":{"position":"top"},"plugins":[{"id":"arun.lock"},{"id":"mirador"}],"disabledPlugins":["omarchy.lock"],"cloneSourceRestores":["arun.lock"]}' \
    > "$DT/home/.config/omarchy/shell.json"
}
SHELL_JSON() { echo "$DT/$1/.config/omarchy/shell.json"; }

test_dotfiles_shell_json_plugin_state_is_not_drift() {
  shell_json_env
  deploy > "$DT/log" 2>&1
  check "same layout counts as identical" lacks "$DT/log" 'changed on this machine|Replaced|Updated'
  check "plugins untouched" has "$(SHELL_JSON home)" 'mirador'
}

test_dotfiles_shell_json_update_keeps_plugin_state() {
  shell_json_env
  deploy > /dev/null 2>&1
  echo '{"version":1,"bar":{"position":"bottom"},"plugins":[]}' > "$(SHELL_JSON repo)"
  deploy > "$DT/log" 2>&1
  check "layout updated" test "$(jq -r .bar.position "$(SHELL_JSON home)")" = bottom
  check "enabled plugins kept" test "$(jq -c '[.plugins[].id]' "$(SHELL_JSON home)")" = '["arun.lock","mirador"]'
  check "stock lock stays disabled" test "$(jq -c .disabledPlugins "$(SHELL_JSON home)")" = '["omarchy.lock"]'
  check "clone restore kept" test "$(jq -c .cloneSourceRestores "$(SHELL_JSON home)")" = '["arun.lock"]'
}

test_dotfiles_shell_json_default_replaced_keeps_plugin_state() {
  shell_json_env
  echo '{"version":1,"bar":{"position":"left"},"plugins":[]}' > "$(SHELL_JSON skel)"
  jq '.bar.position = "left"' "$(SHELL_JSON home)" > "$DT/tmp" && mv "$DT/tmp" "$(SHELL_JSON home)"
  deploy > "$DT/log" 2>&1
  check "treated as Omarchy's default" has "$DT/log" "Replaced Omarchy's default"
  check "repo layout" test "$(jq -r .bar.position "$(SHELL_JSON home)")" = top
  check "plugins kept" has "$(SHELL_JSON home)" 'mirador'
}

test_dotfiles_shell_json_copied_into_repo_without_plugin_state() {
  shell_json_env
  deploy > /dev/null 2>&1
  jq '.bar.position = "right"' "$(SHELL_JSON home)" > "$DT/tmp" && mv "$DT/tmp" "$(SHELL_JSON home)"
  printf 'i\n' | deploy_tty > "$DT/log" 2>&1
  check "layout copied" test "$(jq -r .bar.position "$(SHELL_JSON repo)")" = right
  check "no machine plugins in the repo" test "$(jq -c .plugins "$(SHELL_JSON repo)")" = '[]'
  check "no disabledPlugins in the repo" lacks "$(SHELL_JSON repo)" 'disabledPlugins|cloneSourceRestores'
  deploy > "$DT/log2" 2>&1
  check "no more questions" lacks "$DT/log2" 'changed on this machine'
}

test_dotfiles_fresh_shell_json_gets_no_disabled_lock() {
  shell_json_env
  rm "$(SHELL_JSON home)"
  deploy > /dev/null 2>&1
  check "stock lock screen left enabled" lacks "$(SHELL_JSON home)" 'disabledPlugins'
}

# ------------------------------------------------------------------------------

filter="${1:-}"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  [[ -n "$filter" && "$t" != *"$filter"* ]] && continue
  CURRENT="${t#test_}"
  echo "  ${CURRENT//_/ }"
  "$t"
done
sb_cleanup

echo
echo "$PASSED passed, $FAILED failed"
if (( FAILED )); then
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
