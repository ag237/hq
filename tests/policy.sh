#!/usr/bin/env bash
# Policy tests: things that must stay true as the code changes.
#  1. the permission allowlist hq generates stays small and read-only (it decides what workers/PM do without a prompt)
#  2. input validators reject every hostile input in every locale
#  3. scripts keep LF line endings
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

echo "permission allowlist"
python3 -I - "$HQ_SRC/claude/settings.json" "$HQ_SRC/profiles/_template/settings.json" <<'PY' && ok "allowlist rules are all on the approved list" || bad "allowlist policy violated (details above)"
import json, re, sys
ALLOWED_BASH = [
    r"tmux list-windows(:\*)?", r"tmux list-sessions(:\*)?", r"tmux capture-pane(:\*)?",
    r"\{\{HQ_BIN\}\}/(hq (status|find:\*|park:\*|revive:\*|adopt:\*)|spawn-worker:\*|sync)",
]
FORBIDDEN = ["curl", "wget", "ssh", "scp", "sudo", "rm ", "chmod", "chown", "bash", "sh ", "python", "eval", "kubectl", "talosctl",
             "docker", "git push", "send-keys", "kill", "Write", "Edit", "--force", "delete", "destroy", "remove", "merge"]
def wildcard_problem(body):
    # Claude Code warns about (and mis-matches) these: a * ahead of the last word approves options inserted there, and a * mixed
    # with the trailing :* is matched as a literal prefix, so the rule never fires. Only a trailing :* may contain a *.
    core = body[:-2] if body.endswith(":*") else body
    if "*" in core: return "wildcard before the end of the rule (use an exact value; only a trailing :* is allowed)"
    return None
# self-test: the checker must flag the shapes that caused the startup warning
for r in ("git -C * branch --show-current", "git -C * status:*", "git status * --short"):
    assert wildcard_problem(r), "wildcard check missed: " + r
for r in ("git status:*", "tmux list-windows:*", "x/hq status"):
    assert not wildcard_problem(r), "wildcard check flagged: " + r
bad = 0
for path in sys.argv[1:]:
    for rule in json.load(open(path)).get("permissions", {}).get("allow", []):
        m = re.fullmatch(r"Bash\((.*)\)", rule)
        if m:
            if not any(re.fullmatch(a, m.group(1)) for a in ALLOWED_BASH):
                print(f"  {path}: Bash rule not on the approved list: {rule}"); bad = 1
        elif rule.startswith("mcp__"):
            if re.search(r"delete|destroy|remove|merge|archive|unshare", rule):
                print(f"  {path}: destructive MCP rule: {rule}"); bad = 1
        else:
            print(f"  {path}: unexpected rule type: {rule}"); bad = 1
        if m and any(f in rule for f in FORBIDDEN):
            print(f"  {path}: forbidden word in rule: {rule}"); bad = 1
        if rule in ("Bash", "Bash(*)", "Bash(:*)", "*") or "(*)" in rule:
            print(f"  {path}: blanket rule: {rule}"); bad = 1
        if m and wildcard_problem(m.group(1)):
            print(f"  {path}: {wildcard_problem(m.group(1))}: {rule}"); bad = 1
sys.exit(bad)
PY
"$SB/work/hq/bin/hq" init --name t --team TST --state-repo "$SB/work/hq-state" >/dev/null 2>&1
python3 -I - "$SB/work/.claude/settings.json" <<'PY' && ok "rendered settings.json: every Bash rule is anchored (no bare wildcard)" || bad "rendered settings.json has an unanchored rule"
import json, sys
for r in json.load(open(sys.argv[1]))["permissions"]["allow"]:
    if r.startswith("Bash(") and (r.startswith("Bash(*") or r.startswith("Bash(:")): sys.exit(1)
PY

echo "validators (valid_issue / valid_repo) under hostile input"
# exit 1 means "rejected"; any other code (0 accepted, 127 missing function) fails the test, so it cannot pass vacuously
vi() { LC_ALL="$1" bash -c '. "$1"/bin/lib.sh; valid_issue "$2"' _ "$HQ_SRC" "$2"; }
vr() { LC_ALL="$1" bash -c '. "$1"/bin/lib.sh; valid_repo "$2"' _ "$HQ_SRC" "$2"; }
LOCALES="C"; locale -a 2>/dev/null | grep -qi '^en_US.utf-\?8$' && LOCALES="$LOCALES en_US.UTF-8"; locale -a 2>/dev/null | grep -qix 'C.utf-\?8' && LOCALES="$LOCALES C.UTF-8"
NL="$(printf '\nX')"; NL="${NL%X}"
BADCHARS=(" " "	" "$NL" ";" "|" "&" "\$" "\`" "'" '"' "(" ")" "<" ">" "*" "?" "\\" "/" "~" "!" "#" "{" "}" "[" "]" "=" "%" "^" "," ":" "@" "é" "ß" "日" "٣" "$(printf '\r')" "$(printf '\033')")
for loc in $LOCALES; do
  fail=""
  for c in "${BADCHARS[@]}"; do
    for tmpl in "A${c}B" "${c}AB" "AB${c}"; do
      vi "$loc" "$tmpl"; [ $? = 1 ] || fail="$fail issue:[$tmpl]"
      vr "$loc" "$tmpl"; [ $? = 1 ] || fail="$fail repo:[$tmpl]"
    done
  done
  [ -z "$fail" ] && ok "locale $loc: every special/unicode/control character rejected" || bad "locale $loc: accepted:" "$fail"
done
for loc in $LOCALES; do
  fail=""
  for v in "" "." ".." "-x" ".x" "--rf" "../x" "a/../b" "$(printf 'A%.0s' $(seq 1 65))" "$(printf 'A%.0s' $(seq 1 10000))"; do vi "$loc" "$v"; [ $? = 1 ] || fail="$fail issue:[${v:0:12}]"; done
  for v in "" ".." "." "-x" ".git" "a b" "$(printf 'a%.0s' $(seq 1 101))"; do vr "$loc" "$v"; [ $? = 1 ] || fail="$fail repo:[${v:0:12}]"; done
  [ -z "$fail" ] && ok "locale $loc: empty, dots, leading dash/dot and over-long names rejected" || bad "locale $loc: accepted:" "$fail"
done
good=1; for v in ABC-1 ENG-123 abc_1.2 a "$(printf 'A%.0s' $(seq 1 64))"; do vi C "$v" || good=0; done
for v in argocd my-repo repo_2 a.b; do vr C "$v" || good=0; done; vr C - || good=0
[ "$good" = 1 ] && ok "ordinary ids and repo names are accepted" || bad "validators reject a legitimate name"

echo "line endings"
crlf="$(cd "$HQ_SRC" && { git ls-files 2>/dev/null || find . -type f -not -path './.git/*' | sed 's|^\./||'; } | while read -r f; do [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && grep -q "$(printf '\r')" "$f" && echo "$f"; done)"
[ -z "$crlf" ] && ok "no CRLF line endings in tracked text files" || bad "CRLF line endings" "$crlf"
finish
