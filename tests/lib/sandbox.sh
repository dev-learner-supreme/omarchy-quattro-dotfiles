# shellcheck shell=bash
# shellcheck disable=SC2016  # stub bodies are literal code, expanded when the stub runs
# Throwaway sandbox for exercising install.sh and bin/egismoc-fingerprint
# without an Omarchy machine: a fake $HOME, /etc and USB sysfs, plus stub
# Omarchy/pacman/sudo/fprintd commands that record what they were asked to do.
#
# A copy of the repo has its system paths (/etc/pam.d, /etc/pacman.conf, ...)
# rewritten to point into the sandbox, so nothing outside it is ever touched.
#
# Knobs for the stubs (set in the environment of `sb_run`):
#   SUDO_REAUTH_FAIL=1       `sudo -k` fails (the new PAM stack "doesn't work")
#   CORRUPT_SUDO=1           first write of /etc/pam.d/sudo also drops a line
#   FAIL_ON_POLKIT_WRITE=1   adding fingerprint to /etc/pam.d/polkit-1 fails
#   FAIL_CLONE=1             omarchy-plugin-clone fails
#   SESSION_LOCKED=1         the session is locked

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures"
SB=""

sb_cleanup() { [[ -n "$SB" && -d "$SB" ]] && rm -rf "$SB"; SB=""; }

# sb_fresh [vendor:product]   (default: the Acer's EgisTec 1c7a:0584)
sb_fresh() {
  local sensor="${1:-1c7a:0584}"
  sb_cleanup
  SB="$(mktemp -d)"
  mkdir -p "$SB"/{stubs,state,home,skel,etc/pam.d,usr/lib/pam.d,usr/bin,var/cache,sys/1-3,omarchy/shell/plugins}

  cp -a "$REPO_ROOT" "$SB/repo"
  rm -rf "$SB/repo/.git" "$SB/repo/tests"
  grep -rlE '/etc/pam.d|/usr/lib/pam.d|/etc/pacman.conf|/var/cache/pacman/pkg|-x /usr/bin/omarchy-hw' \
      "$SB/repo" --exclude='*.md' --exclude='*.zst' |
    xargs sed -i -e "s#/etc/pam.d#$SB/etc/pam.d#g" -e "s#/usr/lib/pam.d#$SB/usr/lib/pam.d#g" \
      -e "s#/etc/pacman.conf#$SB/etc/pacman.conf#g" -e "s#/var/cache/pacman/pkg#$SB/var/cache#g" \
      -e "s#-x /usr/bin/omarchy-hw-laptop-closed#-x $SB/usr/bin/omarchy-hw-laptop-closed#g"

  # A stock Arch/Omarchy system: sudo with no fingerprint, polkit only as the
  # vendor copy, pacman.conf without IgnorePkg, lid open.
  printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n' > "$SB/etc/pam.d/sudo"
  printf '#%%PAM-1.0\nauth       include      system-auth\naccount    include      system-auth\npassword   include      system-auth\nsession    include      system-auth\n' > "$SB/usr/lib/pam.d/polkit-1"
  printf '[options]\nHoldPkg     = pacman glibc\n#IgnorePkg   =\nArchitecture = auto\n' > "$SB/etc/pacman.conf"
  printf '#!/bin/bash\nexit 1\n' > "$SB/usr/bin/omarchy-hw-laptop-closed"
  chmod +x "$SB/usr/bin/omarchy-hw-laptop-closed"
  cp -a "$FIXTURES/omarchy/shell/plugins/lock" "$SB/omarchy/shell/plugins/lock"

  echo "${sensor%%:*}" > "$SB/sys/1-3/idVendor"
  echo "${sensor##*:}" > "$SB/sys/1-3/idProduct"
  printf 'fprintd\n' > "$SB/state/installed"
  echo 0 > "$SB/state/prints"
  : > "$SB/state/calls"
  sb_stubs
}

sb_stub() {
  printf '#!/bin/bash\nSB=%q\n%s\n' "$SB" "$2" > "$SB/stubs/$1"
  chmod +x "$SB/stubs/$1"
}

sb_stubs() {
  sb_stub sudo '
case "$1" in
  -v|-n) exit 0 ;;
  -k) [[ -n ${SUDO_REAUTH_FAIL:-} ]] && exit 1; exit 0 ;;
esac
if [[ -n ${CORRUPT_SUDO:-} && $1 == cp && $3 == */pam.d/sudo && ! -e $SB/state/corrupted ]]; then
  "$@"; sed -i "/^account/d" "$3"; touch "$SB/state/corrupted"; exit
fi
# Fails the fingerprint insert into polkit-1, i.e. after sudo was already edited.
if [[ -n ${FAIL_ON_POLKIT_WRITE:-} && $1 == cp && $3 == */pam.d/polkit-1 && $2 != */usr/lib/pam.d/* ]]; then
  echo "sudo: simulated failure" >&2; exit 1
fi
exec "$@"'
  sb_stub pacman '
echo "pacman $*" >> "$SB/state/calls"
case "$1" in
  -Q) shift; rc=0
      for p in "$@"; do if grep -qx "$p" "$SB/state/installed"; then echo "$p 1.0"; else rc=1; fi; done
      exit $rc ;;
  -U) n=$(basename "${@: -1}"); n=${n%%-r[0-9]*}
      grep -vx libfprint "$SB/state/installed" > "$SB/state/i2"; mv "$SB/state/i2" "$SB/state/installed"
      echo "$n" >> "$SB/state/installed" ;;
esac'
  sb_stub omarchy-pkg-missing 'for p in "$@"; do grep -qx "$p" "$SB/state/installed" || exit 0; done; exit 1'
  sb_stub omarchy-pkg-present 'for p in "$@"; do grep -qx "$p" "$SB/state/installed" || exit 1; done; exit 0'
  sb_stub omarchy-pkg-add 'echo "omarchy-pkg-add $*" >> "$SB/state/calls"
for p in "$@"; do grep -qx "$p" "$SB/state/installed" || echo "$p" >> "$SB/state/installed"; done'
  sb_stub omarchy-version 'echo 4.0.4'
  sb_stub omarchy-hw-fingerprint 'exit 0'
  sb_stub omarchy-default-terminal '[[ $# -eq 0 ]] && { echo ghostty; exit 0; }; echo "omarchy-default-terminal $*" >> "$SB/state/calls"'
  sb_stub omarchy-install-terminal 'echo "omarchy-install-terminal $*" >> "$SB/state/calls"; echo "$1" >> "$SB/state/installed"'
  sb_stub omarchy-pkg-aur-accessible 'exit 0'
  sb_stub yay 'exit 0'
  sb_stub omarchy-pkg-aur-add 'echo "omarchy-pkg-aur-add $*" >> "$SB/state/calls"'
  sb_stub omarchy-install-browser 'echo "omarchy-install-browser $*" >> "$SB/state/calls"'
  sb_stub systemctl 'echo "systemctl $*" >> "$SB/state/calls"; [[ "$*" == *is-active* ]] && exit 1; exit 0'
  sb_stub hyprctl 'exit 0'
  sb_stub omarchy-restart-terminal 'exit 0'
  sb_stub omarchy-restart-shell 'echo "omarchy-restart-shell" >> "$SB/state/calls"'
  sb_stub omarchy-shell 'exit 0'
  sb_stub fprintd-list 'n=$(cat "$SB/state/prints"); [[ $1 == root ]] && n=0
echo "Fingerprints for user $1 on EgisTec (press):"
for ((i = 0; i < n; i++)); do echo " - #$i: right-index-finger"; done'
  sb_stub fprintd-enroll 'echo 1 > "$SB/state/prints"; echo "Enroll result: enroll-completed"'
  sb_stub fprintd-verify 'echo "Verify result: verify-match (done)"'
  sb_stub fprintd-delete 'echo "fprintd-delete $*" >> "$SB/state/calls"'
  sb_stub omarchy-plugin-clone '[[ -n ${FAIL_CLONE:-} ]] && exit 1
d="$HOME/.config/omarchy/plugins/${USER}.lock"; [[ -e $d ]] && exit 1
mkdir -p "$d"; cp -aL "$OMARCHY_PATH/shell/plugins/lock/." "$d/"
sed -i "s/\"id\": \"omarchy.lock\"/\"id\": \"${USER}.lock\"/" "$d/manifest.json"
echo "omarchy-plugin-clone $*" >> "$SB/state/calls"'
  sb_stub omarchy-plugin-remove 'rm -rf "$HOME/.config/omarchy/plugins/$1"; echo "omarchy-plugin-remove $*" >> "$SB/state/calls"'
  sb_stub omarchy-plugin-enable 'echo "omarchy-plugin-enable $*" >> "$SB/state/calls"'
  sb_stub omarchy-hyprland-session-locked '[[ -n ${SESSION_LOCKED:-} ]] && exit 0; exit 1'
  sb_stub omarchy-notification-send 'printf "notify:" >> "$SB/state/calls"; printf " [%s]" "$@" >> "$SB/state/calls"; echo >> "$SB/state/calls"'
  sb_stub omarchy-setup-security-fingerprint 'echo "omarchy-setup-security-fingerprint" >> "$SB/state/calls"'
  sb_stub curl 'exit 1'
  # Stands in for a real gum (installed on Omarchy), which reads the terminal
  # directly and would hang on piped answers. Echoes the typed answer, which
  # the scripts' prompt parsing accepts just like a menu choice.
  sb_stub gum '
cmd="$1"; shift; default=true
for a in "$@"; do [[ $a == --default=* ]] && default="${a#--default=}"; done
IFS= read -r answer || answer=""
case "$cmd" in
  choose)  echo "$answer" ;;
  confirm) [[ -z $answer ]] && { [[ $default == true ]]; exit; }; [[ $answer == [Yy]* ]] ;;
esac'
}

# Runs a command as the sandbox user, with the stubs first on PATH. Extra
# environment goes in front: sb_run env FAIL_CLONE=1 cmd ...
sb_run() {
  env -i HOME="$SB/home" USER=arun TERM=dumb LANG=C.UTF-8 \
    PATH="$SB/stubs:$SB/home/.local/bin:/usr/bin:/bin" \
    OMARCHY_USB_DEVICES_PATH="$SB/sys" OMARCHY_PATH="$SB/omarchy" OMARCHY_SKEL="$SB/skel" \
    "$@"
}

# Same, but on a pseudo-terminal so prompts are interactive; stdin feeds answers.
sb_run_tty() {
  local cmd
  printf -v cmd '%q ' "$@"
  sb_run script -qec "$cmd" /dev/null
}
