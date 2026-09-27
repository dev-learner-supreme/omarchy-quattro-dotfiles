# shellcheck shell=bash
# shellcheck disable=SC2088  # "~/" in messages is for display only
#
# Dotfile deployment for install.sh. Copies the repo's files into $HOME, but:
#   - never silently overwrites a file that changed on this machine since it
#     was last deployed (by you, an Omarchy migration, or an app) — it asks;
#   - removes files that were deleted from the repo, if they're unchanged.
#
# The repo root mirrors $HOME, so a path like .config/hypr/bindings.lua means
# the same file in both. Needs DOTFILES_DIR, BACKUP_DIR, ASSUME_YES, lib/ui.sh.

DOTFILES_STATE="${DOTFILES_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-dotfiles/deployed}"
# Omarchy seeds a new user's $HOME from /etc/skel (and resets from it), so a
# file identical to its /etc/skel copy is an untouched Omarchy default.
OMARCHY_SKEL="${OMARCHY_SKEL:-/etc/skel}"

declare -A DEPLOYED=()   # path -> sha256 of the content this script last wrote
DOTFILES_KEPT=()

# shell.json mixes the bar layout with per-machine plugin state: which plugins
# are switched on (they're installed per machine, not from this repo), and
# disabledPlugins, which can switch off Omarchy's own lock screen. The repo
# tracks only the layout; every comparison ignores these keys, and a deploy
# keeps the machine's own values for them.
MACHINE_STATE_FILE=".config/omarchy/shell.json"
MACHINE_STATE_KEYS='["plugins","disabledPlugins","cloneSourceRestores"]'

has_machine_state() { [[ "$1" == "$MACHINE_STATE_FILE" ]]; }

# The part of FILE the repo manages. Invalid JSON is compared as-is.
managed_content() {
  local rel="$1" file="$2"
  if has_machine_state "$rel" &&
     jq -S --argjson k "$MACHINE_STATE_KEYS" 'with_entries(select(.key as $x | $k | index($x) | not))' "$file" 2>/dev/null; then
    return 0
  fi
  cat "$file"
}

same_content() { cmp -s <(managed_content "$1" "$2") <(managed_content "$1" "$3"); }
content_hash() { managed_content "$1" "$2" | sha256sum | cut -d' ' -f1; }

managed_paths() {
  (
    cd "$DOTFILES_DIR" || exit 1
    find .config .local -type f 2>/dev/null || true
    local f
    for f in .bashrc .zshrc; do
      if [[ -f "$f" ]]; then echo "$f"; fi
    done
  ) | sort
}

load_deployed() {
  DEPLOYED=()
  [[ -f "$DOTFILES_STATE" ]] || return 0
  local hash path
  while read -r hash path; do
    if [[ -n "$path" ]]; then DEPLOYED["$path"]="$hash"; fi
  done < "$DOTFILES_STATE"
}

save_deployed() {
  mkdir -p "$(dirname "$DOTFILES_STATE")"
  local path tmp
  tmp="$(mktemp)"
  for path in "${!DEPLOYED[@]}"; do
    printf '%s  %s\n' "${DEPLOYED[$path]}" "$path"
  done | sort -k2 > "$tmp"
  mv "$tmp" "$DOTFILES_STATE"
}

backup_home_file() {
  mkdir -p "$BACKUP_DIR/$(dirname "$1")"
  cp -p "$HOME/$1" "$BACKUP_DIR/$1"
}

install_from_repo() {
  local rel="$1" src="$DOTFILES_DIR/$1" dest="$HOME/$1" merged=""
  mkdir -p "$(dirname "$dest")"
  if has_machine_state "$rel" && [[ -f "$dest" ]]; then
    merged="$(jq --slurpfile live "$dest" --argjson k "$MACHINE_STATE_KEYS" \
      '. + ($live[0] | with_entries(select(.key as $x | $k | index($x))))' "$src" 2>/dev/null || true)"
  fi
  if [[ -n "$merged" ]]; then
    printf '%s\n' "$merged" > "$dest"   # repo layout, this machine's plugin state
  else
    cp -p "$src" "$dest"
  fi
  DEPLOYED["$rel"]="$(content_hash "$rel" "$src")"
}

# Copies ~/REL into the repo, minus any per-machine state.
copy_into_repo() {
  local rel="$1" stripped=""
  if has_machine_state "$rel"; then
    stripped="$(jq --argjson k "$MACHINE_STATE_KEYS" \
      'with_entries(select(.key as $x | $k | index($x) | not)) | .plugins = []' "$HOME/$rel" 2>/dev/null || true)"
  fi
  if [[ -n "$stripped" ]]; then
    printf '%s\n' "$stripped" > "$DOTFILES_DIR/$rel"
  else
    cp -p "$HOME/$rel" "$DOTFILES_DIR/$rel"
  fi
}

# Prints keep, repo, or pull. Unattended runs always keep the local file.
# Called inside $(...), so stdout is never a terminal: check stdin/stderr.
ask_about_drift() {
  local rel="$1" answer
  if (( ASSUME_YES )) || [[ ! -t 0 || ! -t 2 ]]; then
    echo keep
    return 0
  fi
  while true; do
    if command -v gum &>/dev/null; then
      answer="$(gum choose --header "What should happen to ~/$rel?" \
        "Keep mine" "Use the repo's version" "Copy mine into the repo" "Show the difference")" || answer="Keep mine"
    else
      read -rp "  [k]eep mine, use the [r]epo's, copy mine [i]nto the repo, show [d]ifference (k): " answer
    fi
    case "${answer,,}" in
      "use the repo's version"|r*) echo repo; return 0 ;;
      "copy mine into the repo"|i*) echo pull; return 0 ;;
      "show the difference"|d*)
        diff -u --label "repo: $rel" --label "this machine: ~/$rel" \
          <(managed_content "$rel" "$DOTFILES_DIR/$rel") <(managed_content "$rel" "$HOME/$rel") >&2 || true ;;
      *) echo keep; return 0 ;;
    esac
  done
}

deploy_one() {
  local rel="$1" src="$DOTFILES_DIR/$1" dest="$HOME/$1" current

  if [[ -L "$dest" ]]; then
    warn "~/$rel is a symlink (managed by another tool) — left alone."
    return 0
  fi
  if [[ ! -e "$dest" ]]; then
    install_from_repo "$rel"
    info "Added: ~/$rel"
    return 0
  fi
  if same_content "$rel" "$src" "$dest"; then
    DEPLOYED["$rel"]="$(content_hash "$rel" "$src")"
    return 0
  fi

  current="$(content_hash "$rel" "$dest")"
  # Still exactly what this script put there last time: the repo moved on.
  if [[ "${DEPLOYED[$rel]:-}" == "$current" ]]; then
    install_from_repo "$rel"
    info "Updated: ~/$rel"
    return 0
  fi
  # An Omarchy default nobody has touched: replacing it is the whole point.
  if [[ -f "$OMARCHY_SKEL/$rel" ]] && same_content "$rel" "$OMARCHY_SKEL/$rel" "$dest"; then
    backup_home_file "$rel"
    install_from_repo "$rel"
    info "Replaced Omarchy's default: ~/$rel"
    return 0
  fi

  warn "~/$rel has changed on this machine since it was last deployed (by you, an Omarchy update, or an app)."
  case "$(ask_about_drift "$rel")" in
    repo)
      backup_home_file "$rel"
      install_from_repo "$rel"
      info "Replaced with the repo's version; yours is saved in $BACKUP_DIR/$rel"
      ;;
    pull)
      copy_into_repo "$rel"
      DEPLOYED["$rel"]="$current"
      info "Copied into the repo — review and commit it: git -C \"$DOTFILES_DIR\" diff -- $rel"
      ;;
    *)
      DOTFILES_KEPT+=("$rel")
      ;;
  esac
}

# Files this script deployed earlier that are no longer in the repo.
prune_removed() {
  local -A managed=()
  local rel dest
  for rel in "$@"; do managed["$rel"]=1; done

  for rel in "${!DEPLOYED[@]}"; do
    [[ -n "${managed[$rel]:-}" ]] && continue
    dest="$HOME/$rel"
    if [[ -f "$dest" && ! -L "$dest" ]]; then
      if [[ "$(content_hash "$rel" "$dest")" == "${DEPLOYED[$rel]}" ]]; then
        backup_home_file "$rel"
        rm -f "$dest"
        info "Removed (deleted from the repo): ~/$rel"
      elif confirm "~/$rel was deleted from the repo, but it changed on this machine. Delete it anyway? (a backup is kept)" false; then
        backup_home_file "$rel"
        rm -f "$dest"
        info "Removed: ~/$rel"
      else
        info "Kept ~/$rel — it's no longer managed by the repo."
      fi
    fi
    unset "DEPLOYED[$rel]"
  done
}

dotfiles_deploy() {
  local -a paths
  local rel
  mapfile -t paths < <(managed_paths)
  load_deployed
  for rel in "${paths[@]}"; do
    deploy_one "$rel"
  done
  prune_removed "${paths[@]}"
  save_deployed

  if (( ${#DOTFILES_KEPT[@]} )); then
    warn "Kept your version of ${#DOTFILES_KEPT[@]} changed file(s), not deployed:"
    for rel in "${DOTFILES_KEPT[@]}"; do echo "    ~/$rel" >&2; done
    warn "Run ./install.sh without -y to review them (keep, use the repo's, or copy yours into the repo)."
  fi
}
