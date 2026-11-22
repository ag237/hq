#!/usr/bin/env bash
# Static checks for the public repo: syntax, shellcheck, portability, secrets, personal data, workflow hardening.
# Usage: tests/lint.sh        (CI=1 makes a missing shellcheck a failure)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
FAIL=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/        /'; }
FILES="$(git ls-files 2>/dev/null)"; [ -n "$FILES" ] || FILES="$(find . -type f -not -path './.git/*' -not -path './worktrees/*' | sed 's|^\./||')"
SCRIPTS="$(printf '%s\n' "$FILES" | grep -E '^(bin/[^.]+|tests/.*\.sh|hooks/[^.]+)$')"
# shellcheck disable=SC2086
scripts() { for f in $SCRIPTS; do [ -f "$f" ] && printf '%s\n' "$f"; done; }

echo "syntax + shellcheck"
for f in $(scripts); do bash -n "$f" 2>/tmp/hq-lint.$$ && ok "bash -n $f" || bad "bash -n $f" "$(cat /tmp/hq-lint.$$)"; done; rm -f /tmp/hq-lint.$$
if command -v shellcheck >/dev/null 2>&1; then
  out="$(scripts | xargs shellcheck -S warning 2>&1)" && ok "shellcheck (warning+)" || bad "shellcheck" "$out"
elif [ -n "${CI:-}" ]; then bad "shellcheck not installed"; else echo "  skip  shellcheck not installed"; fi

echo "portability (bash 3.2 / macOS / no GNU-only tools)"
PORT='readlink -f|flock|declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|date -I|sed -i|grep -P|sed -r|xargs -r|stat -c|\becho -e\b|\bsetsid\b'
hits="$(for f in $(scripts); do [ "$f" = tests/lint.sh ] && continue; grep -nE "$PORT" "$f" | grep -v 'lint:allow' | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"; done)"
[ -z "$hits" ] && ok "no GNU-only or bash 4+ constructs" || bad "non-portable constructs" "$hits"

echo "dangerous constructs"
hits="$(for f in $(scripts); do [ "$f" = tests/lint.sh ] && continue; grep -nE '(^|[;&|[:space:]])eval[[:space:]]|curl[^|]*\|[[:space:]]*(ba)?sh|chmod[[:space:]]+(-R[[:space:]]+)?[0-7]*7[0-7]*[[:space:]]|rm -rf[[:space:]]+/[[:space:]]|--dangerously' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"; done)"
[ -z "$hits" ] && ok "no eval, curl|sh, world-writable chmod, or permission bypass flags" || bad "dangerous constructs" "$hits"

echo "files"
for f in $(printf '%s\n' "$FILES" | grep -E '\.json$'); do python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$f" 2>/dev/null && ok "valid JSON $f" || bad "invalid JSON $f"; done
for f in $(scripts); do [ -x "$f" ] && ok "executable $f" || bad "not executable: $f"; done
bad_perm="$(printf '%s\n' "$FILES" | grep -E '\.(pem|key)$|(^|/)\.env$')"; [ -z "$bad_perm" ] && ok "no .env/.pem/.key files tracked" || bad "tracked secret-type files" "$bad_perm"

echo "secrets"
# the pattern list itself and this script legitimately contain pattern text
scan="$(printf '%s\n' "$FILES" | grep -vE '^(secret-patterns\.txt)$')"
# shellcheck disable=SC2086
hits="$(printf '%s\n' "$scan" | xargs grep -nIE -f secret-patterns.txt 2>/dev/null | cut -d: -f1,2 | sed 's/$/  (matched text withheld)/')"   # file:line only: never print the secret
[ -z "$hits" ] && ok "no credential-shaped strings in tracked files" || bad "credential-shaped strings" "$hits"
if git rev-parse --git-dir >/dev/null 2>&1; then
  n="$(git log -p --all --no-color 2>/dev/null | grep '^+' | grep -v '^+++' | grep -v 'lint:allow' | grep -cE -f secret-patterns.txt)"; hits=""; [ "${n:-0}" = 0 ] || hits="$n added line(s) in history match a credential pattern (text withheld; use git log -p -G to locate)"
  [ -z "$hits" ] && ok "no credential-shaped strings anywhere in git history" || bad "credential-shaped strings in history" "$hits"
fi

echo "personal / environment data"
PERSONAL='/home/[a-z][a-z0-9_-]*/|/Users/[A-Za-z][A-Za-z0-9_-]*/|(^|[^0-9.])(10\.[0-9]+|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'
# shellcheck disable=SC2086
hits="$(printf '%s\n' "$scan" | xargs grep -nIE "$PERSONAL" 2>/dev/null | grep -vE 'example\.(com|org)|noreply@(anthropic|github)\.com|users\.noreply\.github\.com|/home/user/|/Users/you/|/Users/name/|\$HOME|test@example' | cut -c1-140)"
[ -z "$hits" ] && ok "no home paths, private IPs or email addresses" || bad "personal-looking data" "$hits"
# machine-local denylist: your own names, hostnames, tracker keys, internal domains (one extended regex per line); never committed
DL="${XDG_CONFIG_HOME:-$HOME/.config}/hq/denylist"
if [ -f "$DL" ]; then
  # shellcheck disable=SC2086
  hits="$(printf '%s\n' "$scan" | xargs grep -nIiE -f "$DL" 2>/dev/null | cut -c1-140)"
  [ -z "$hits" ] && ok "denylist ($DL) has no hits" || bad "denylist hits" "$hits"
else echo "  skip  no local denylist at $DL (put one regex per line there: your names, hosts, internal domains)"; fi

echo "workflows"
if ls .github/workflows/*.yml >/dev/null 2>&1; then
  hits="$(grep -nE '^[[:space:]]*-?[[:space:]]*uses:' .github/workflows/*.yml | grep -vE 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$)' )"
  [ -z "$hits" ] && ok "every action is pinned to a full commit SHA" || bad "unpinned actions" "$hits"
  grep -lE 'pull_request_target|workflow_run' .github/workflows/*.yml >/dev/null 2>&1 && bad "pull_request_target/workflow_run used (runs untrusted code with secrets)" || ok "no pull_request_target/workflow_run"
  for f in .github/workflows/*.yml; do grep -qE '^permissions:' "$f" && ok "$f sets top-level permissions" || bad "$f has no top-level permissions block"; done
  grep -nE '\$\{\{[[:space:]]*github\.(event\.(issue|pull_request|comment|head_commit)|head_ref)' .github/workflows/*.yml >/dev/null 2>&1 && bad "untrusted github.event text interpolated in a workflow (script injection)" || ok "no untrusted event text interpolated"
fi

echo
[ "$FAIL" = 0 ] && echo "lint: ok" || echo "lint: $FAIL problem(s)"
[ "$FAIL" = 0 ]
