#!/usr/bin/env bash
# End-to-end tests of hq in a sandbox. Usage: tests/run.sh
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

echo "init"
refuse "init refuses workdir == \$HOME" "$HQ" init --name t --workdir "$HOME"
check "init --state-repo" "$HQ" init --name t --team TST --user-name Tess --state-repo "$STATE_REPO" --remote "$SB/remote.git"
check "state repo is a separate git repo" test -d "$STATE_REPO/.git"
check "env points at state repo" contains "$HOME/.config/hq/env" "HQ_STATE_DIR=$STATE_REPO/state/$HOST"
check "sync enabled once origin exists" contains "$HOME/.config/hq/env" "HQ_SYNC=on"
check "profile created in state repo" test -f "$STATE_REPO/profiles/t/profile.env"
PV="$SB/pv.sh"   # prints USER_NAME|TEAM|ISSUE_EXAMPLE as bash sees them after sourcing a profile's profile.env
printf '#!/bin/bash\n. "%s/profiles/$1/profile.env"; printf "%%s|%%s|%%s" "$USER_NAME" "$TEAM" "$ISSUE_EXAMPLE"\n' "$STATE_REPO" > "$PV"; chmod +x "$PV"
check "USER_NAME written to profile (as sourced)" bash -c '[ "$("$1" t)" = "Tess|TST|TST-123" ]' _ "$PV"
check "doctor passes" "$HQ" doctor
echo "init values (profile.env is sourced by bash, so they are validated and quoted)"
check "init with a two-word name and an explicit example id" "$HQ" init --name v1 --team ABC --user-name "Tess Q" --issue-example ABC-42 --state-repo "$STATE_REPO"
check "  ...both are sourced back intact" bash -c '[ "$("$1" v1)" = "Tess Q|ABC|ABC-42" ]' _ "$PV"
check "init defaults the example id to <TEAM>-123" "$HQ" init --name v2 --team XYZ --user-name Tess --state-repo "$STATE_REPO"
check "  ...so no CHANGEME-123 leaks into a profile that has a team" bash -c '[ "$("$1" v2)" = "Tess|XYZ|XYZ-123" ]' _ "$PV"
refuse "init rejects a name with command substitution" "$HQ" init --name v3 --user-name 'x$(touch PWNED)' --state-repo "$STATE_REPO"
refuse "init rejects a name with a quote" "$HQ" init --name v3 --user-name "a'b" --state-repo "$STATE_REPO"
refuse "init rejects an issue example with a path" "$HQ" init --name v3 --issue-example '../x' --state-repo "$STATE_REPO"
refuse "init rejects a team with shell characters" "$HQ" init --name v3 --team 'A;B' --state-repo "$STATE_REPO"
check "a rejected init created nothing" bash -c '[ ! -e "$1/profiles/v3" ] && ! find "$2" -name PWNED | grep -q .' _ "$STATE_REPO" "$SB"
check "init --prompt asks for both and uses the answers" bash -c 'printf "Pat\nPRJ-7\n" | "$1" init --name p1 --team PRJ --prompt --state-repo "$2" >/dev/null 2>&1 && [ "$("$3" p1)" = "Pat|PRJ|PRJ-7" ]' _ "$HQ" "$STATE_REPO" "$PV"
check "init --prompt: empty answers take the defaults" bash -c 'printf "\n\n" | "$1" init --name p2 --team PRJ --prompt --state-repo "$2" >/dev/null 2>&1 && [ "$("$3" p2)" = "Test|PRJ|PRJ-123" ]' _ "$HQ" "$STATE_REPO" "$PV"
check "init --prompt only asks for what the flags left out" bash -c 'printf "PRJ-9\n" | "$1" init --name p3 --team PRJ --user-name Sam --prompt --state-repo "$2" >/dev/null 2>&1 && [ "$("$3" p3)" = "Sam|PRJ|PRJ-9" ]' _ "$HQ" "$STATE_REPO" "$PV"
check "without a terminal init never waits for input" bash -c '"$1" init --name p4 --team PRJ --state-repo "$2" </dev/null >/dev/null 2>&1 && [ "$("$3" p4)" = "Test|PRJ|PRJ-123" ]' _ "$HQ" "$STATE_REPO" "$PV"
check "push check ran and created nothing on the remote" bash -c '"$1" doctor | grep -q "can reach and push" && [ -z "$(git --git-dir="$2" for-each-ref)" ]' _ "$HQ" "$SB/remote.git"
git -C "$STATE_REPO" remote set-url origin "$SB/no-such-remote.git"
refuse "doctor fails when origin is unreachable" "$HQ" doctor
check "failure explains itself and names the usual fix" bash -c '"$1" doctor 2>&1 | grep -q "cannot talk to origin" && "$1" doctor 2>&1 | grep -q "gh auth setup-git"' _ "$HQ"
git -C "$STATE_REPO" remote set-url origin "$SB/remote.git"
check "doctor passes again once origin is back" "$HQ" doctor

echo "generated config"
check "pm.md rendered" test -s "$SB/work/.claude/agents/pm.md"
if grep -rn '{{' "$SB/work/.claude" >/dev/null 2>&1; then bad "no unrendered {{placeholders}}" "$(grep -rn '{{' "$SB/work/.claude" | head -3)"; else ok "no unrendered {{placeholders}}"; fi
check "settings.json is valid JSON" python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$SB/work/.claude/settings.json"
check "PM addressed by USER_NAME" contains "$SB/work/.claude/agents/pm.md" "Tess"
check "no HQ_BIN placeholder text leaked" bash -c '! grep -q "HQ_BIN" "$1"' _ "$SB/work/.claude/settings.json"
check "both Linear connector namings are allowed" bash -c 'grep -q "mcp__linear-server__get_issue" "$1" && grep -q "mcp__claude_ai_Linear__get_issue" "$1"' _ "$SB/work/.claude/settings.json"
check "no git -C wildcard rules (they warn at startup or never match)" bash -c '! grep -q "git -C" "$1"' _ "$SB/work/.claude/settings.json"
check "Backup line: sync pushes the state repo, not the app repo" bash -c 'grep -q "never synced" "$1" && ! grep -q "is a git repo; .bin/sync. pushes it" "$1"' _ "$SB/work/.claude/agents/pm.md"

echo "input validation (no injection, no traversal)"
S="$SB/work/hq/bin/spawn-worker"
refuse "issue id with command substitution" "$S" --ops 'X$(touch PWNED)' "b"
refuse "issue id with ; and quotes"        "$S" --ops "A';touch PWNED;'" "b"
refuse "issue id path traversal"           "$S" --ops '../../etc' "b"
refuse "issue id leading dash"             "$S" --ops '-rf' "b"
refuse "repo path traversal"               "$S" '../x' ABC-1 "b"
refuse "repo with slash"                   "$S" 'a/b' ABC-1 "b"
refuse "hq park rejects bad id"            "$HQ" park 'x;y'
refuse "hq revive rejects bad id"          "$HQ" revive '$(id)'
refuse "hq adopt rejects bad id"           "$HQ" adopt 11111111-1111-1111-1111-111111111111 'a b'
refuse "reap-worker rejects bad id"        "$SB/work/hq/bin/reap-worker" '../x'
check "nothing was created by the attempts" bash -c '! find "$1" -name PWNED | grep -q .' _ "$SB"
check "board still empty" test ! -s "$STATE_REPO/state/$HOST/board.tsv"

echo "workers"
check "hq up starts the PM" "$HQ" up
sleep 1
check "PM window exists" bash -c 'tmux -L "$1" list-windows -t hq -F "#W" | grep -qx pm' _ "$SOCK"
check "PM launched on the profile model" contains "$SB/claude.log" "--model opus --agent pm"
check "spawn ops worker (shell metachars stay inert in the brief)" "$S" --ops OPS-1 'do $(touch PWNED) `touch PWNED2` "quoted"'
sleep 1
check "worker window exists" bash -c 'tmux -L "$1" list-windows -t hq -F "#W" | grep -qx OPS-1' _ "$SOCK"
check "worker on the profile worker model" contains "$SB/claude.log" "--model sonnet --session-id"
check "brief kept verbatim in file only" contains "$STATE_REPO/state/$HOST/briefs/OPS-1.md" '$(touch PWNED)'
check "brief injection did not execute" bash -c '! find "$1" -name "PWNED*" | grep -q .' _ "$SB"
refuse "duplicate spawn refused" "$S" --ops OPS-1 "again"
check "spawn --plan" "$S" --ops --plan PLAN-1 "plan it"
sleep 1
check "plan worker: plan mode on opusplan" contains "$SB/claude.log" "--model opusplan --permission-mode plan"
check "plan worker model pinned for resumes" contains "$STATE_REPO/state/$HOST/models/PLAN-1" "opusplan"
check "spawn --model override" "$S" --ops --model haiku MOD-1 "x"
sleep 1
check "override model used" contains "$SB/claude.log" "--model haiku --session-id"
check "park closes window, keeps row" bash -c '"$1" park OPS-1 && ! tmux -L "$2" list-windows -t hq -F "#W" | grep -qx OPS-1 && grep -q "OPS-1.*parked" "$3"' _ "$HQ" "$SOCK" "$STATE_REPO/state/$HOST/board.tsv"
check "revive reopens, pinned model kept" bash -c '"$1" revive PLAN-1 >/dev/null; "$1" park PLAN-1 >/dev/null; "$1" revive PLAN-1' _ "$HQ"
sleep 1
check "revive re-applied the pinned model" bash -c 'grep -c -- "--model opusplan" "$1" | grep -qv "^[01]$"' _ "$SB/claude.log"
check "hq down" "$HQ" down
check "hq up rebuilds active workers" bash -c '"$1" up >/dev/null; sleep 1; tmux -L "$2" list-windows -t hq -F "#W" | grep -qx MOD-1' _ "$HQ" "$SOCK"

echo "worktree worker + trust"
git init -q "$SB/work/demo"; (cd "$SB/work/demo" && git commit -q --allow-empty -m init)
printf '{"projects":{}}\n' > "$CLAUDE_JSON"
check "spawn worktree worker (repo untrusted)" "$S" demo WT-1 "change"
check "worktree created" test -d "$SB/work/hq/worktrees/demo/WT-1"
check "untrusted repo: worktree NOT auto-trusted" bash -c '! grep -q WT-1 "$1"' _ "$CLAUDE_JSON"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$SB/work/demo" > "$CLAUDE_JSON"
check "spawn second worker (repo trusted)" "$S" demo WT-2 "change"
check "trusted repo: worktree auto-trusted" contains "$CLAUDE_JSON" "WT-2"
check "reap removes worktree" "$SB/work/hq/bin/reap-worker" WT-2
check "reap removed trust entry" bash -c '! grep -q WT-2 "$1"' _ "$CLAUDE_JSON"
check "reap keeps the row as done" grep -q 'WT-2.*done' "$STATE_REPO/state/$HOST/board.tsv"

echo "adopt"
mkdir -p "$SB/work/moved-to"
ENC="$(printf '%s' "$SB/work" | sed 's/[^a-zA-Z0-9]/-/g')"; mkdir -p "$HOME/.claude/projects/$ENC"
U1=22222222-2222-4222-8222-222222222222; U2=33333333-3333-4333-8333-333333333333
printf '{"type":"user","cwd":"%s"}\n{"type":"user","cwd":"%s"}\n' "$SB/work" "$SB/work/moved-to" > "$HOME/.claude/projects/$ENC/$U1.jsonl"
printf '{"type":"user","cwd":"%s"}\n{"type":"user","cwd":"%s"}\n' "$SB/work" "$SB/work" > "$HOME/.claude/projects/$ENC/$U2.jsonl"
check "adopt a session that moved: warns about the last cwd" bash -c '"$1" adopt "$2" MOVED-1 2>&1 >/dev/null | grep -q "later moved to $3"' _ "$HQ" "$U1" "$SB/work/moved-to"
check "adopt keeps the first cwd on the board (transcript is found by it)" awk -F'\t' -v c="$SB/work" -v u="$U1" '$1=="MOVED-1" && $3==c && $4==u {f=1} END{exit !f}' "$STATE_REPO/state/$HOST/board.tsv"
check "adopt of a session that never moved: no warning" bash -c '[ -z "$("$1" adopt "$2" STAY-1 2>&1 >/dev/null)" ]' _ "$HQ" "$U2"

echo "remote workers (local stub server verifies the V2 signature; ssh is a stub; no real host is contacted)"
RP="$STATE_REPO/profiles/t/remotes"; RB="$STATE_REPO/state/$HOST/board.tsv"
refuse "--remote for an unconfigured remote is refused" "$S" --remote myremote REM-0 "x"
refuse "remote name must be lowercase letters, digits, dashes" "$S" --remote 'My_Remote' REM-0 "x"
refuse "--remote cannot be combined with --ops" "$S" --remote myremote --ops REM-0 "x"
SECRET="$SB/remote.secret"; printf 'sekrit-%s' "$(printf 'z%.0s' $(seq 1 20))" > "$SECRET"; chmod 600 "$SECRET"
python3 -I "$HQ_SRC/tests/remote_stub.py" "$SECRET" "$SB/stub.port" "$SB/stub.log" & STUB_PID=$!
for _ in $(seq 1 50); do [ -s "$SB/stub.port" ] && break; sleep 0.1; done
PORT="$(cat "$SB/stub.port")"
mkdir -p "$RP"
printf 'REMOTE_URL=http://127.0.0.1:%s/webhooks/pm-task\nREMOTE_SECRET_FILE=%s\nREMOTE_SSH=myremote-pm\nREMOTE_STATUS_CMD=%s\nREMOTE_LABEL=myremote\n' "$PORT" "$SECRET" "'~/bin/pm-status'" > "$RP/myremote.env"
cat > "$SB/stubs/ssh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$SB/ssh.log"
case "\$*" in *" recent") echo '{"state":"finished"}'; echo '{"state":"working"}';; *) echo '{"state":"working","started":1,"ended":null,"end_reason":null,"last_activity":2,"last_activity_desc":"x","tools":3,"tokens":4}';; esac
STUB
chmod +x "$SB/stubs/ssh"
check "spawn --remote adds a row, no tmux window" bash -c '"$1" --remote myremote REM-1 "do the thing" && sleep 1 && ! tmux -L "$2" list-windows -t hq -F "#W" | grep -qx REM-1' _ "$S" "$SOCK"
check "board row: @name, cwd -, uuid -, active" awk -F'\t' '$1=="REM-1" && $2=="@myremote" && $3=="-" && $4=="-" && $5=="active" {f=1} END{exit !f}' "$RB"
check "brief stored" contains "$STATE_REPO/state/$HOST/briefs/REM-1.md" "do the thing"
refuse "a second spawn for the same issue is refused" "$S" --remote myremote REM-1 "again"
NONCE="$("$SB/work/hq/bin/remote-task" --new-nonce)"
check "--new-nonce prints 32 hex characters" bash -c '[ "$(printf %s "$1" | grep -cE "^[0-9a-f]{32}$")" = 1 ]' _ "$NONCE"
refuse "remote-task rejects a malformed nonce" "$SB/work/hq/bin/remote-task" --nonce XYZ REM-1 start
refuse "remote-task rejects an unknown mode" "$SB/work/hq/bin/remote-task" --nonce "$NONCE" REM-1 restart
RT="$SB/work/hq/bin/remote-task"
OUTF="$SB/rt.out"; "$RT" --nonce "$NONCE" REM-1 start > "$OUTF" 2>&1; RC=$?
check "remote-task start: exit 0, accepted, nonce echoed" bash -c '[ "$1" = 0 ] && grep -q "^accepted REM-1 mode=start request-id=REM-1-[0-9]* nonce=$2$" "$3"' _ "$RC" "$NONCE" "$OUTF"
check "stub verified the signature and the exact contract (JSON body, headers, route)" python3 -I - "$SB/stub.log" "$NONCE" <<'PY'
import json, re, sys
r = [json.loads(l) for l in open(sys.argv[1])][0]
assert r["verdict"] == "202", r
assert r["ct"] == "application/json" and r["path"] == "/webhooks/pm-task"
assert r["body"] == '{"issue":"REM-1","mode":"start","nonce":"%s"}' % sys.argv[2], r["body"]
assert re.fullmatch(r"REM-1-\d+", r["rid"]) and re.fullmatch(r"\d+", r["ts"])
PY
check "board uuid column holds the request id" bash -c 'awk -F"\t" "\$1==\"REM-1\"{print \$4}" "$1" | grep -qE "^REM-1-[0-9]+$"' _ "$RB"
cut -c1-9 "$SECRET" > "$SB/needle"   # via a file: the checker's own argv must not contain the secret
check "the secret never appears in output, state, argv log or process list" bash -c '! grep -rqF -f "$4" "$1" "$2" "$3" 2>/dev/null && ! ps -eo args | grep -qF -f "$4"' _ "$OUTF" "$STATE_REPO" "$SB/claude.log" "$SB/needle"
"$RT" --nonce "$NONCE" REM-1 start > "$OUTF" 2>&1; "$RT" --nonce "$NONCE" REM-1 start >> "$OUTF" 2>&1
check "a repeat of the same nonce reuses its request id and is reported as duplicate" bash -c '[ "$(grep -c "^duplicate REM-1 mode=start request-id=$2 " "$1")" = 2 ]' _ "$OUTF" "$(awk -F'\t' '$1=="REM-1"{print $4}' "$RB")"
refuse "a used nonce cannot be sent for another mode" "$RT" --nonce "$NONCE" REM-1 followup
check "stub got the same request id each time (never a new id for a nonce)" bash -c '[ "$(grep -c "\"rid\": \"$2\"" "$1")" = 3 ]' _ "$SB/stub.log" "$(awk -F'\t' '$1=="REM-1"{print $4}' "$RB")"
"$S" --remote myremote DUP-1 "x" >/dev/null; "$RT" --nonce "$("$RT" --new-nonce)" DUP-1 start > "$OUTF" 2>&1; RC=$?
check "200 status=duplicate -> 'duplicate', exit 0" bash -c '[ "$1" = 0 ] && grep -q "^duplicate DUP-1" "$2"' _ "$RC" "$OUTF"
"$S" --remote myremote ODD-1 "x" >/dev/null; "$RT" --nonce "$("$RT" --new-nonce)" ODD-1 start > "$OUTF" 2>&1; RC=$?
check "a 200 whose body is not status=duplicate is an error, not a duplicate" bash -c '[ "$1" = 1 ] && ! grep -q "^duplicate" "$2" && grep -q "unexpected 200" "$2"' _ "$RC" "$OUTF"
"$S" --remote myremote GATE-1 "x" >/dev/null; "$RT" --nonce "$("$RT" --new-nonce)" GATE-1 start > "$OUTF" 2>&1; RC=$?
check "200 status=ignored -> gated, exit 6, clear message" bash -c '[ "$1" = 6 ] && grep -q "gate dropped the event" "$2"' _ "$RC" "$OUTF"
"$S" --remote myremote RATE-1 "x" >/dev/null; "$RT" --nonce "$("$RT" --new-nonce)" RATE-1 start > "$OUTF" 2>&1; RC=$?
check "429 -> exit 4" bash -c '[ "$1" = 4 ] && grep -q "rate-limited" "$2"' _ "$RC" "$OUTF"
printf 'other-secret' > "$SB/wrong.secret"; chmod 600 "$SB/wrong.secret"
sed "s|^REMOTE_SECRET_FILE=.*|REMOTE_SECRET_FILE=$SB/wrong.secret|" "$RP/myremote.env" > "$RP/badsig.env"
"$S" --remote badsig BADSIG-1 "x" >/dev/null; "$RT" --nonce "$("$RT" --new-nonce)" BADSIG-1 start > "$OUTF" 2>&1; RC=$?
check "bad signature -> 404 -> exit 3" bash -c '[ "$1" = 3 ] && grep -q "bad signature" "$2"' _ "$RC" "$OUTF"
chmod 644 "$SB/wrong.secret"; "$RT" --nonce "$("$RT" --new-nonce)" BADSIG-1 start > "$OUTF" 2>&1; RC=$?
check "a secret file readable by others is refused (exit 1) before anything is sent" bash -c '[ "$1" = 1 ] && grep -q "chmod 600" "$2"' _ "$RC" "$OUTF"
"$S" --remote myremote FLAKY-1 "x" >/dev/null; HQ_REMOTE_RETRY_WAIT=1 "$RT" --nonce "$("$RT" --new-nonce)" FLAKY-1 start > "$OUTF" 2>&1; RC=$?
check "dropped connection: retried, accepted" bash -c '[ "$1" = 0 ] && grep -q "^accepted FLAKY-1" "$2"' _ "$RC" "$OUTF"
check "retry kept the request id and body but was re-signed with a fresh timestamp" python3 -I - "$SB/stub.log" <<'PY'
import json, sys
r = [x for x in map(json.loads, open(sys.argv[1])) if x["rid"].startswith("FLAKY-1-")]
assert [x["verdict"] for x in r] == ["dropped", "202"], r
assert r[0]["rid"] == r[1]["rid"] and r[0]["body"] == r[1]["body"] and r[0]["ts"] != r[1]["ts"], r
PY
DEADPORT="$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"   # a port nothing listens on
sed "s|^REMOTE_URL=.*|REMOTE_URL=http://127.0.0.1:$DEADPORT/webhooks/pm-task|" "$RP/myremote.env" > "$RP/down.env"
"$S" --remote down DOWN-1 "x" >/dev/null; HQ_REMOTE_RETRY_WAIT=0 "$RT" --nonce "$("$RT" --new-nonce)" DOWN-1 start > "$OUTF" 2>&1; RC=$?
check "a negative HQ_REMOTE_RETRY_WAIT is clamped cleanly (no traceback)" bash -c 'out="$(HQ_REMOTE_RETRY_WAIT=-1 "$1" --nonce "$2" DOWN-1 start 2>&1)"; ! printf "%s" "$out" | grep -q Traceback' _ "$RT" "$("$RT" --new-nonce)"
check "no connection -> exit 5" bash -c '[ "$1" = 5 ] && grep -q "no connection" "$2"' _ "$RC" "$OUTF"
refuse "remote-task on a non-remote row is refused" "$RT" --nonce "$NONCE" OPS-1 start
refuse "remote-task on an unknown issue needs --remote" "$RT" --nonce "$NONCE" NOPE-1 start
refuse "remote-task without --nonce sends nothing" bash -c 'n=$(wc -l < "$2"); "$1" REM-1 start 2>"$3"; rc=$?; [ "$rc" = 2 ] && grep -q "nonce is required" "$3" && [ "$(wc -l < "$2")" = "$n" ]; [ "$rc" != 2 ]' _ "$RT" "$SB/stub.log" "$SB/nonce.err"
refuse "profile file with an option-like REMOTE_SSH is rejected" bash -c 'sed "s|^REMOTE_SSH=.*|REMOTE_SSH=-oProxyCommand=x|" "$1" > "$2"; "$3" --remote evil EVIL-1 x' _ "$RP/myremote.env" "$RP/evil.env" "$S"
RS="$SB/work/hq/bin/remote-status"
check "remote-status runs the status command over ssh with the request id" bash -c 'out="$("$1" REM-1)"; echo "$out" | grep -q "\"state\":\"working\"" && grep -qE -- "-- myremote-pm ~/bin/pm-status status REM-1-[0-9]+$" "$2"' _ "$RS" "$SB/ssh.log"
check "remote-status --recent" bash -c '[ "$("$1" --recent myremote | wc -l)" = 2 ] && grep -q "pm-status recent$" "$2"' _ "$RS" "$SB/ssh.log"
check "remote-status for a row nothing was sent to: state none, no ssh" bash -c 'n=$(wc -l < "$2"); "$3" --remote myremote NONE-1 x >/dev/null; [ "$("$1" NONE-1)" = "{\"state\":\"none\"}" ] && [ "$(wc -l < "$2")" = "$n" ]' _ "$RS" "$SB/ssh.log" "$S"
check "hq status lists remote workers as remote:<name>" bash -c '"$1" status | grep -q "REM-1 *remote:myremote *active"' _ "$HQ"
"$HQ" down >/dev/null 2>&1; "$HQ" up >/dev/null 2>&1; sleep 1
check "hq up never opens a window for a remote row" bash -c '! tmux -L "$1" list-windows -t hq -F "#W" | grep -qx REM-1 && tmux -L "$1" list-windows -t hq -F "#W" | grep -qx MOD-1' _ "$SOCK"
check "hq park: row only, says the remote keeps running" bash -c '"$1" park REM-1 | grep -q "does NOT stop the remote" && grep -q "REM-1.*parked" "$2"' _ "$HQ" "$RB"
: > "$SB/stub.log"; N2="$("$RT" --new-nonce)"
check "hq revive on a remote row sends a follow-up with the nonce and re-activates it" bash -c '"$1" revive REM-1 --nonce "$2" | grep -q "^accepted REM-1 mode=followup" && grep -q "REM-1.*active" "$3"' _ "$HQ" "$N2" "$RB"
check "  ...the stub saw mode=followup" bash -c 'grep "$1" "$2" | grep -q "followup"' _ "$N2" "$SB/stub.log"
check "hq revive on a remote row without --nonce sends nothing and says to post the comment first" bash -c 'n=$(wc -l < "$2"); "$1" revive REM-1 2>"$3"; rc=$?; [ "$rc" = 2 ] && grep -q "\[PM\] brief nonce=[0-9a-f]\{32\} mode=followup" "$3" && grep -q "then run: hq revive REM-1 --nonce" "$3" && [ "$(wc -l < "$2")" = "$n" ]' _ "$HQ" "$SB/stub.log" "$SB/revive.err"
: > "$SB/stub.log"
"$S" --remote myremote SAME-1 "x" >/dev/null
check "two nonces for one issue in the same second get different request ids" bash -c 'a=$("$1" --nonce "$2" SAME-1 start); b=$("$1" --nonce "$3" SAME-1 start); ia=${a#*request-id=}; ia=${ia%% *}; ib=${b#*request-id=}; ib=${ib%% *}; [ -n "$ia" ] && [ "$ia" != "$ib" ] && printf "%s\n%s\n" "$a" "$b" | grep -c "^accepted" | grep -q 2' _ "$RT" "$("$RT" --new-nonce)" "$("$RT" --new-nonce)"
refuse "a profile with an empty REMOTE_STATUS_CMD is rejected" bash -c 'sed "s|^REMOTE_STATUS_CMD=.*|REMOTE_STATUS_CMD=|" "$1" > "$2"; "$3" --remote nocmd NOCMD-1 x' _ "$RP/myremote.env" "$RP/nocmd.env" "$S"
refuse "a REMOTE_STATUS_CMD with shell characters is rejected" bash -c 'sed "s|^REMOTE_STATUS_CMD=.*|REMOTE_STATUS_CMD=\"x;id\"|" "$1" > "$2"; "$3" --remote badcmd BADCMD-1 x' _ "$RP/myremote.env" "$RP/badcmd.env" "$S"
refuse "a REMOTE_LABEL with odd characters is rejected" bash -c 'sed "s|^REMOTE_LABEL=.*|REMOTE_LABEL=a b|" "$1" > "$2"; "$3" --remote badlabel BADLBL-1 x' _ "$RP/myremote.env" "$RP/badlabel.env" "$S"
refuse "a profile with an empty REMOTE_SSH is rejected" bash -c 'sed "s|^REMOTE_SSH=.*|REMOTE_SSH=|" "$1" > "$2"; "$3" --remote nossh NOSSH-1 x' _ "$RP/myremote.env" "$RP/nossh.env" "$S"
check "reap-worker on a remote row: row only, done" bash -c '"$1" REM-1 | grep -q "nothing on the remote was touched" && grep -q "REM-1.*done" "$2"' _ "$SB/work/hq/bin/reap-worker" "$RB"
check "docs: dispatch/checkin/review/park mention remote rows" bash -c 'cd "$1"; grep -q "remote-task" dispatch.md && grep -q "remote-status" checkin.md && grep -q "Remote rows" review.md && grep -q "does not stop the remote" park.md' _ "$SB/work/.claude/commands"
"$HQ" config >/dev/null 2>&1
check "docs: dispatch documents the gated exit and the nonce comment" bash -c 'grep -q "gated" "$1" && grep -q "\[PM\] brief nonce=<nonce> mode=start" "$1"' _ "$SB/work/.claude/commands/dispatch.md"
kill "$STUB_PID" 2>/dev/null; STUB_PID=

echo "autostart (launchd plist checked with plistlib; launchctl itself needs a real Mac)"
PL="$SB/plist.xml"
check "autostart show launchd" bash -c '"$1" autostart show launchd > "$2" 2> "$3"' _ "$HQ" "$PL" "$SB/plist.err"
check "plist: label, args, RunAtLoad, log paths, fixed PATH" python3 -I - "$PL" "$HQ" "$HOME" <<'PY'
import os, plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); hq, home = sys.argv[2], sys.argv[3]
log = home + "/Library/Logs/hq/autostart.log"
assert d["Label"] == "net.hq.up"
assert d["ProgramArguments"] == [hq, "up"], d["ProgramArguments"]
assert d["RunAtLoad"] is True
assert d["StandardOutPath"] == log and d["StandardErrorPath"] == log, (d.get("StandardOutPath"), d.get("StandardErrorPath"))
path = d["EnvironmentVariables"]["PATH"]
assert path == home + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", path
assert path != os.environ["PATH"], "PATH was frozen from the caller's environment"
PY
check "plist: log dir is outside the state repo" bash -c '! grep -q "$1" "$2"' _ "$STATE_REPO" "$PL"
check "missing tool on the launchd PATH is reported with the fix" bash -c 'grep -q "claude. is not on the PATH" "$1" && grep -q "PATH=.*\$PATH:$2" "$1"' _ "$SB/plist.err" "$SB/stubs"
cp "$HOME/.config/hq/env" "$SB/env.bak"; printf 'PATH="$PATH:%s"\n' "$SB/stubs" >> "$HOME/.config/hq/env"
check "PATH line in ~/.config/hq/env satisfies the check" bash -c '"$1" autostart show launchd 2>&1 >/dev/null | grep -q .; [ $? -ne 0 ]' _ "$HQ"
mv "$SB/env.bak" "$HOME/.config/hq/env"
cp -R "$SB/work/hq" "$SB/work/a&b"
check "XML-special characters in the install path are escaped" bash -c '"$1" autostart show launchd 2>/dev/null | python3 -I -c "import plistlib,sys;d=plistlib.loads(sys.stdin.buffer.read());assert d[\"ProgramArguments\"][0]==sys.argv[1]" "$1"' _ "$SB/work/a&b/bin/hq"
check "autostart show systemd" bash -c '"$1" autostart show systemd | grep -q "^ExecStart=$2/bin/hq up"' _ "$HQ" "$SB/work/hq"
refuse "autostart show rejects an unknown target" "$HQ" autostart show nonsense

echo "sync"
SYNC="$SB/work/hq/bin/sync"
check "sync pushes state" "$SYNC"
check "remote has the state files" bash -c 'git --git-dir="$1" ls-tree -r --name-only main | grep -q "board.tsv"' _ "$SB/remote.git"
check "app copy never committed to the state repo" bash -c '! git --git-dir="$1" ls-tree -r --name-only main | grep -q "^bin/"' _ "$SB/remote.git"
check "second sync is a no-op" bash -c '"$1" | grep -q "up to date"' _ "$SYNC"
FAKE="ghp_$(printf 'A%.0s' $(seq 1 36))"
echo "token=$FAKE" > "$STATE_REPO/state/$HOST/briefs/leak.md"
refuse "sync refuses a credential" "$SYNC"
check "refused change left uncommitted" bash -c '[ -n "$(git -C "$1" status --porcelain)" ]' _ "$STATE_REPO"
rm "$STATE_REPO/state/$HOST/briefs/leak.md"
check "sync works again once removed" "$SYNC"
echo "heartbeat"
HB="$STATE_REPO/state/$HOST/heartbeat"
check "status without heartbeat" bash -c '"$1" status | grep -q "none yet"' _ "$HQ"
printf '%s checkin ok · active 1 · sync up-to-date\n' "$(date +%Y-%m-%dT%H:%M)" > "$HB"
check "status shows heartbeat and age" bash -c '"$1" status | grep -q "checkin ok.*(age 0m"' _ "$HQ"
printf '2020-01-01T00:00 checkin ok · active 0 · sync off\n' > "$HB"
check "old heartbeat flagged STALE" bash -c '"$1" status | grep -q "STALE"' _ "$HQ"
check "sync with a heartbeat present" "$SYNC"
check "heartbeat never committed or pending" bash -c '[ -z "$(git -C "$1" status --porcelain)" ] && ! git -C "$1" ls-files | grep -q heartbeat' _ "$STATE_REPO"
check "checkin documents heartbeat and long-wait push" bash -c 'grep -q "/heartbeat" "$1" && grep -q "long-wait" "$1"' _ "$SB/work/.claude/commands/checkin.md"
mkdir -p "$SB/cfg2/hq" "$SB/work/hq/state/x"
printf 'HQ_SYNC=on\nHQ_STATE_DIR=%s\n' "$SB/work/hq/state/x" > "$SB/cfg2/hq/env"
git -C "$SB/work/hq" init -q
refuse "sync refuses state inside the app repo" env XDG_CONFIG_HOME="$SB/cfg2" "$SYNC"
check "HQ_SYNC=off is a no-op" env HQ_SYNC=off "$SYNC"
git -C "$STATE_REPO" remote set-url origin "$SB/no-such-remote.git"
echo "x" > "$STATE_REPO/state/$HOST/briefs/after-outage.md"
check "sync exits 2 and names the cause when origin cannot be used" bash -c 'out="$("$1" 2>&1)"; rc=$?; [ "$rc" = 2 ] && printf "%s" "$out" | grep -q "cannot talk to origin"' _ "$SYNC"
git -C "$STATE_REPO" remote set-url origin "$SB/remote.git"
check "sync recovers once origin is back" "$SYNC"

finish
