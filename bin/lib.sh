# shared helpers; source after setting HQ_DIR
HQ_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hq"
# shellcheck disable=SC1091
[ -f "$HQ_CONF/env" ] && . "$HQ_CONF/env"     # machine-local: may set HQ_PROFILE, HQ_WORKDIR, HQ_STATE_DIR, HQ_SYNC

# Working directory = where the project repos live and where the PM runs. Default: the parent of hq/.
HOME_DIR="${HQ_WORKDIR:-$(dirname "$HQ_DIR")}"
PROJ_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
WT_ROOT="$HQ_DIR/worktrees"        # worktrees live at $WT_ROOT/<repo>/<ISSUE> (gitignored, per machine)
SESSION=hq

# State: board, briefs, logs, PM session id. Default state/<hostname>/ in the repo; set HQ_STATE_DIR to keep it elsewhere.
HQ_HOST="${HQ_HOST:-$(hostname -s)}"
STATE="${HQ_STATE_DIR:-$HQ_DIR/state/$HQ_HOST}"
BOARD="$STATE/board.tsv"           # issue<TAB>repo<TAB>cwd<TAB>uuid<TAB>status<TAB>updated   (repo "-" = ops worker)
BRIEFS="$STATE/briefs"; LOGS="$STATE/logs"; PM_FILE="$STATE/pm.session"

# Profile = what differs per environment (tracker team, repo map, extra rules).
# A local profile in ~/.config/hq/profiles/<name>/ (never committed) wins over the repo's profiles/<name>/.
PROFILE="${HQ_PROFILE:-$(cat "$HQ_CONF/profile" 2>/dev/null || true)}"   # no default: run `hq init` first
# Lookup order: $HQ_PROFILES_DIR (e.g. inside your private state repo), ~/.config/hq/profiles, then the app repo's profiles/.
PROFILES_DIR="${HQ_PROFILES_DIR:-$HQ_CONF/profiles}"
if [ -n "$PROFILE" ] && [ -d "$PROFILES_DIR/$PROFILE" ]; then PROFILE_DIR="$PROFILES_DIR/$PROFILE"
elif [ -n "$PROFILE" ] && [ -d "$HQ_CONF/profiles/$PROFILE" ]; then PROFILE_DIR="$HQ_CONF/profiles/$PROFILE"
else PROFILE_DIR="$HQ_DIR/profiles/$PROFILE"; fi
USER_NAME="the user"
TEAM=TEAM ISSUE_EXAMPLE=ISSUE-1 HQ_PM_MODEL="" HQ_WORKER_MODEL=""
MODELS="$STATE/models"             # per-worker model overrides: one file per issue
MEMORY_DIR="$PROJ_DIR/$(printf '%s' "$HOME_DIR" | sed 's/[^a-zA-Z0-9]/-/g')/memory"
_tilde='~'                         # via a variable: quoting of a literal ~ in ${..//} differs between bash 3.2 and 4+
HQ_BIN="${HQ_DIR/#$HOME/$_tilde}/bin"   # tilde form: what commands and permission rules use

# Call at the top of every command that needs a configured install (everything except init/doctor).
need_profile() {
  if [ -z "$PROFILE" ] || [ ! -d "$PROFILE_DIR" ]; then
    echo "hq: no profile configured ('${PROFILE:-none}'). Run '$HQ_DIR/bin/hq init' to set this machine up." >&2; exit 1
  fi
  # shellcheck disable=SC1091
  . "$PROFILE_DIR/profile.env"
  if [ "$(cd "$HOME_DIR" 2>/dev/null && pwd -P)" = "$(cd "$HOME" && pwd -P)" ]; then
    echo "hq: the working directory is \$HOME, which would overwrite your global ~/.claude. Put hq inside a dedicated directory (e.g. ~/work/hq) or set HQ_WORKDIR." >&2; exit 1
  fi
  mkdir -p "$BRIEFS" "$LOGS" "$MODELS"; [ -e "$BOARD" ] || : > "$BOARD"
}

# Fill {{placeholders}} in a template read from stdin.
render() {
  sed -e "s|{{HQ_DIR}}|$HQ_DIR|g" -e "s|{{HQ_BIN}}|$HQ_BIN|g" -e "s|{{STATE}}|$STATE|g" \
      -e "s|{{HOME_DIR}}|$HOME_DIR|g" -e "s|{{MEMORY_DIR}}|$MEMORY_DIR|g" \
      -e "s|{{TEAM}}|$TEAM|g" -e "s|{{ISSUE_EXAMPLE}}|$ISSUE_EXAMPLE|g" -e "s|{{PROFILE}}|$PROFILE|g" -e "s|{{USER_NAME}}|$USER_NAME|g"
}

# ---- portability helpers (no GNU-only tools) ----
now() { date +%Y-%m-%dT%H:%M:%S%z; }
new_uuid() { { uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())'; } | tr 'A-Z' 'a-z'; }
tmo() { # tmo <seconds> cmd...   (GNU timeout, Homebrew gtimeout, or no timeout)
  local s=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else "$@"; fi
}

# tmux wrapper. HQ_SOCKET selects a private tmux server (tests); unset = the normal one.
tm() { tmux ${HQ_SOCKET:+-L "$HQ_SOCKET"} "$@"; }
has_window() { tm list-windows -t "$SESSION" -F '#W' 2>/dev/null | grep -qx "$1"; }

board_row() { [ -s "$BOARD" ] && awk -F'\t' -v i="$1" '$1==i' "$BOARD" || true; }
board_set() { # <issue> <status>
  awk -F'\t' -v OFS='\t' -v i="$1" -v s="$2" -v d="$(now)" '$1==i{$5=s;$6=d}1' "$BOARD" > "$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
}

# Claude stores transcripts under a dir named after the cwd with non-alnum -> '-'.
transcript_exists() { # <cwd> <uuid>
  local enc; enc="$(printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g')"
  [ -f "$PROJ_DIR/$enc/$2.jsonl" ]
}

make_worktree() { # <repo_dir> <wt> <branch>
  local repo_dir=$1 wt=$2 branch=$3 base
  git -C "$repo_dir" worktree prune
  mkdir -p "$(dirname "$wt")"
  git -C "$repo_dir" fetch -q origin 2>/dev/null || true
  if git -C "$repo_dir" show-ref -q --verify "refs/heads/$branch"; then
    git -C "$repo_dir" worktree add "$wt" "$branch"
  else
    base="$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo HEAD)"
    git -C "$repo_dir" worktree add -b "$branch" "$wt" "$base"
  fi
}

# " --model X" (leading space) for the PM / a worker, or nothing. A per-issue override beats the profile default.
pm_model_flag() { [ -n "$HQ_PM_MODEL" ] && printf ' --model %s' "$HQ_PM_MODEL" || true; }
worker_model_flag() { # <issue>
  local m="$HQ_WORKER_MODEL"; [ -s "$MODELS/$1" ] && m="$(cat "$MODELS/$1")"
  [ -n "$m" ] && printf ' --model %s' "$m" || true
}

# open a window for a worker, resuming its pinned session if the transcript exists
start_worker() { # <issue> <repo> <cwd> <uuid>
  local issue=$1 repo=$2 cwd=$3 uuid=$4 cmd
  [ -d "$cwd" ] || { echo "hq: $cwd missing for $issue" >&2; return 1; }
  [ "$repo" = "-" ] || "$HQ_DIR/bin/trust-path" "$cwd" "$HOME_DIR/$repo" || true
  if transcript_exists "$cwd" "$uuid"; then
    cmd="claude$(worker_model_flag "$issue") --resume $uuid -n $issue"
  else
    cmd="claude$(worker_model_flag "$issue") --session-id $uuid -n $issue 'Your session was rebuilt and has no saved conversation. Re-read $BRIEFS/$issue.md, check git status/log (if you have a worktree) and the tracker issue comments, then continue.'"
  fi
  if tm has-session -t "$SESSION" 2>/dev/null; then
    tm new-window -d -t "$SESSION:" -n "$issue" -c "$cwd" "$cmd"
  else
    tm new-session -d -s "$SESSION" -n "$issue" -c "$cwd" "$cmd"
  fi
}
