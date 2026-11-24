# shellcheck shell=bash disable=SC2034
# shared helpers; source after setting HQ_DIR (SC2034: variables are consumed by the scripts that source this)
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
BOARD="$STATE/board.tsv"           # issue<TAB>repo<TAB>cwd<TAB>uuid<TAB>status<TAB>updated   (repo "-" = ops worker, "@name" = remote worker)
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
  umask "$(printf '%03o' $(( $(umask) | 022 )))"   # never create group/world-writable files, whatever the caller's umask (a CI runner may use 000)
  mkdir -p "$BRIEFS" "$LOGS" "$MODELS"; chmod 700 "$STATE" 2>/dev/null || true   # briefs/logs hold issue text: owner only
  [ -e "$BOARD" ] || : > "$BOARD"
}

# Escape a value for use inside a sed s|..|HERE|g replacement (\\, & and the | delimiter).
sedq() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Fill {{placeholders}} in a template read from stdin.
render() {
  sed -e "s|{{HQ_DIR}}|$(sedq "$HQ_DIR")|g" -e "s|{{HQ_BIN}}|$(sedq "$HQ_BIN")|g" -e "s|{{STATE}}|$(sedq "$STATE")|g" \
      -e "s|{{HOME_DIR}}|$(sedq "$HOME_DIR")|g" -e "s|{{MEMORY_DIR}}|$(sedq "$MEMORY_DIR")|g" \
      -e "s|{{TEAM}}|$(sedq "$TEAM")|g" -e "s|{{ISSUE_EXAMPLE}}|$(sedq "$ISSUE_EXAMPLE")|g" -e "s|{{PROFILE}}|$(sedq "$PROFILE")|g" \
      -e "s|{{USER_NAME}}|$(sedq "$USER_NAME")|g"
}

# Input validation. Issue ids and repo names end up in file paths, branch names, tmux window names and shell command
# strings, and they can come from tracker text via the PM, so only a conservative character set is accepted.
valid_issue() { case "$1" in ""|-*|*[!A-Za-z0-9._-]*|.*) return 1;; esac; [ "${#1}" -le 64 ]; }
valid_repo() { [ "$1" = "-" ] && return 0; case "$1" in ""|-*|.*|*[!A-Za-z0-9._-]*) return 1;; esac; [ "${#1}" -le 100 ]; }
# A display name that ends up in profile.env (sourced by bash), sed replacements and prompt text: reject shell/sed metacharacters and control chars.
valid_name() { case "$1" in ""|*[\'\"\\\$\`\|\&\;\<\>\(\)\{\}\*\?\#\~\!]*|*[[:cntrl:]]*) return 1;; esac; [ "${#1}" -le 40 ]; }
need_issue() { valid_issue "$1" || { echo "hq: invalid issue id '$1' (letters, digits, . _ - only; max 64)" >&2; exit 2; }; }
need_repo() { valid_repo "$1" || { echo "hq: invalid repo name '$1' (letters, digits, . _ - only, not starting with . or -)" >&2; exit 2; }; }
# Remote workers: a board row whose repo column is "@<name>" is run by an external agent, not in tmux. <name> selects
# $PROFILE_DIR/remotes/<name>.env (private, per environment). Names are lowercase letters, digits and dashes.
is_remote() { case "$1" in @*) return 0;; esac; return 1; }
valid_remote() { case "$1" in ""|-*|*[!a-z0-9-]*) return 1;; esac; [ "${#1}" -le 40 ]; }
need_remote() { valid_remote "$1" || { echo "hq: invalid remote name '$1' (lowercase letters, digits, - only; max 40)" >&2; exit 2; }; }
valid_nonce() { case "$1" in *[!0-9a-f]*) return 1;; esac; [ "${#1}" -eq 32 ]; }
valid_request_id() { case "$1" in ""|-*|*[!A-Za-z0-9._-]*) return 1;; esac; [ "${#1}" -le 100 ]; }
# Load $PROFILE_DIR/remotes/<name>.env and check it. Sets REMOTE_URL REMOTE_SECRET_FILE REMOTE_SSH REMOTE_STATUS_CMD REMOTE_LABEL.
# The file is shell (like profile.env) and lives in the private profile; the values are still validated before use.
load_remote() { # <name>
  local name=$1 f
  need_remote "$name"
  f="$PROFILE_DIR/remotes/$name.env"
  [ -f "$f" ] || { echo "hq: no remote '$name' (expected $f)" >&2; exit 1; }
  REMOTE_URL="" REMOTE_SECRET_FILE="$HQ_CONF/remotes/$name.secret" REMOTE_SSH="" REMOTE_STATUS_CMD="" REMOTE_LABEL="$name"
  # shellcheck disable=SC1090
  . "$f"
  case "$REMOTE_URL" in http://?*|https://?*) ;; *) echo "hq: remote '$name': REMOTE_URL must be an http(s) URL" >&2; exit 1;; esac
  case "$REMOTE_URL" in *[[:space:]]*) echo "hq: remote '$name': REMOTE_URL contains whitespace" >&2; exit 1;; esac
  case "$REMOTE_SSH" in ""|-*|*[!A-Za-z0-9._@-]*) echo "hq: remote '$name': REMOTE_SSH must be set to a host or ssh-config alias (letters, digits, . _ @ - only; not starting with -)" >&2; exit 1;; esac
  case "$REMOTE_STATUS_CMD" in ""|*[!A-Za-z0-9._/~@+:-]*) echo "hq: remote '$name': REMOTE_STATUS_CMD must be set to a command path without spaces or shell characters (letters, digits, . _ / ~ @ + : - only)" >&2; exit 1;; esac
  case "$REMOTE_LABEL" in ""|*[!A-Za-z0-9_-]*) echo "hq: remote '$name': REMOTE_LABEL must be letters, digits, _ and - only" >&2; exit 1;; esac
  [ "${#REMOTE_LABEL}" -le 40 ] || { echo "hq: remote '$name': REMOTE_LABEL is longer than 40 characters" >&2; exit 1; }
  case "$REMOTE_SECRET_FILE" in /*) ;; *) echo "hq: remote '$name': REMOTE_SECRET_FILE must be an absolute path" >&2; exit 1;; esac
}

q() { printf '%q' "$1"; }          # shell-quote a value that is embedded in a tmux command string

# ---- portability helpers (no GNU-only tools) ----
now() { date +%Y-%m-%dT%H:%M:%S%z; }
new_uuid() { { uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())'; } | tr 'A-Z' 'a-z'; }
tmo() { # tmo <seconds> cmd...   (GNU timeout, Homebrew gtimeout, or no timeout)
  local s=$1; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else "$@"; fi
}

# Can git reach and authenticate to the state repo's origin with nobody at the keyboard (no password, no ssh passphrase)?
# bin/sync runs unattended, so a prompt means it fails. READ-ONLY: ls-remote, then a --dry-run push of a throwaway empty commit
# (a dry run only talks to the remote; nothing is ever created there). Prints a diagnosis to stderr on failure, nothing on success.
sync_check() { # <repo>
  local repo=$1 out rc=0
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || { echo "sync check: $repo has no origin remote" >&2; return 1; }
  out="$( ( export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes"
            export GIT_AUTHOR_NAME=hq GIT_AUTHOR_EMAIL=hq@localhost GIT_COMMITTER_NAME=hq GIT_COMMITTER_EMAIL=hq@localhost
            cd "$repo" || exit 1
            tmo 30 git ls-remote --heads origin >/dev/null || exit 1
            obj="$(git commit-tree "$(git hash-object -t tree -w /dev/null)" -m "hq push check")" || exit 1
            tmo 30 git push --dry-run -q origin "$obj:refs/heads/hq-push-check" >/dev/null ) 2>&1 )" || rc=$?
  [ "$rc" != 0 ] || return 0
  {
    echo "sync check: git cannot talk to origin without a prompt, so bin/sync would fail (exit 2). git said:"
    # first lines only, with any user:password@ in a URL masked
    printf '%s\n' "$out" | grep -v '^$' | head -3 | sed -E -e 's#(://)[^/@[:space:]]*@#\1***@#g' -e 's/^/    /'
    echo "  Fix the credentials, then re-run 'hq doctor'. GitHub over HTTPS: 'gh auth setup-git'. Other HTTPS hosts: configure a git"
    echo "  credential helper. SSH: the key must be usable without a passphrase prompt (ssh-add it to a running ssh-agent)."
  } >&2
  return 1
}

# tmux wrapper. HQ_SOCKET selects a private tmux server (tests); unset = the normal one.
tm() { tmux ${HQ_SOCKET:+-L "$HQ_SOCKET"} "$@"; }
has_window() { tm list-windows -t "$SESSION" -F '#W' 2>/dev/null | grep -qx "$1"; }

board_row() { [ -s "$BOARD" ] && awk -F'\t' -v i="$1" '$1==i' "$BOARD" || true; }
board_set() { # <issue> <status>
  awk -F'\t' -v OFS='\t' -v i="$1" -v s="$2" -v d="$(now)" '$1==i{$5=s;$6=d}1' "$BOARD" > "$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
}

board_set_uuid() { # <issue> <uuid-or-request-id>: the uuid column holds a remote row's last X-Request-ID
  awk -F'\t' -v OFS='\t' -v i="$1" -v u="$2" -v d="$(now)" '$1==i{$4=u;$6=d}1' "$BOARD" > "$BOARD.tmp" && mv "$BOARD.tmp" "$BOARD"
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
    cmd="claude$(worker_model_flag "$issue") --resume $uuid -n $(q "$issue")"
  else
    cmd="claude$(worker_model_flag "$issue") --session-id $uuid -n $(q "$issue") $(q "Your session was rebuilt and has no saved conversation. Re-read $BRIEFS/$issue.md, check git status/log (if you have a worktree) and the tracker issue comments, then continue.")"
  fi
  if tm has-session -t "$SESSION" 2>/dev/null; then
    tm new-window -d -t "$SESSION:" -n "$issue" -c "$cwd" "$cmd"
  else
    tm new-session -d -s "$SESSION" -n "$issue" -c "$cwd" "$cmd"
  fi
}
