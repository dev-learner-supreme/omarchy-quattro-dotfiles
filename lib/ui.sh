# shellcheck shell=bash
# Shared helpers for install.sh and bin/egismoc-fingerprint. Source, don't run.
# Expects ASSUME_YES to be set by the caller (0 or 1).

log()  { echo -e "\e[32m\n$*\e[0m"; }
info() { echo -e "\e[34m:: $*\e[0m"; }
warn() { echo -e "\e[33mWarning: $*\e[0m" >&2; }
fail() { echo -e "\e[31mError: $*\e[0m" >&2; exit 1; }

# confirm "<prompt>" [true|false]. Under -y it returns the default answer, so
# default-No questions stay No in unattended runs.
confirm() {
  local prompt="$1"
  local default="${2:-true}"
  if (( ASSUME_YES )); then
    [[ "$default" == "true" ]]
    return
  fi

  if [[ -t 0 && -t 1 ]] && command -v gum &>/dev/null; then
    gum confirm --default="$default" "$prompt"
  elif [[ -t 0 && -t 1 ]]; then
    local yn
    if [[ "$default" == "true" ]]; then
      read -rp "$prompt [Y/n]: " yn
      [[ -z "$yn" || "$yn" =~ ^[Yy] ]]
    else
      read -rp "$prompt [y/N]: " yn
      [[ "$yn" =~ ^[Yy] ]]
    fi
  else
    warn "Non-interactive terminal; pass -y to accept defaults."
    return 1
  fi
}

# Authorize sudo once and keep the timestamp fresh until the caller exits.
# The subshell drops inherited traps and errexit so a failed refresh can never
# fire the caller's ERR trap from the background, and it detaches from stdout
# so a pipe like `./install.sh | tee log` isn't held open by its sleep.
start_sudo_keepalive() {
  sudo -v || fail "sudo authorization failed. Run this from a terminal where you can enter your password."
  ( trap - ERR INT TERM EXIT; set +e
    while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 60; done ) </dev/null >/dev/null 2>&1 &
  SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null || true   # the pending sleep
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  return 0
}

omarchy_shell_up() {
  command -v omarchy-shell &>/dev/null &&
    OMARCHY_SHELL_IPC_TIMEOUT=1s omarchy-shell shell ping &>/dev/null
}
