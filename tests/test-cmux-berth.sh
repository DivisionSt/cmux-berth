#!/usr/bin/env bash
#
# Regression harness for bin/cmux-berth.
#
#   bash tests/test-cmux-berth.sh bin/cmux-berth
#
# WHY THIS EXISTS. cmux-berth opens a remote tmux session as a cmux sidebar row
# inside its repo's group. Every way it can go wrong is quiet: a second row for
# a session that already has one, a row filed under the wrong group, a group
# created twice, or a tmux target the remote shell rewrites. cmux and the
# remote are both out of reach from a test, so this shadows ssh, cmux and fzf
# with stubs and asserts on the exact calls it makes.

set -uo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    printf 'usage: %s <path-to-executable_cx>\n' "$0" >&2
    exit 2
fi
SRC=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")

WORK=$(mktemp -d) || exit 2
trap 'rm -rf "$WORK"' EXIT
export WORK

pass=0; fail=0
ok()  { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$3] got [$2]"; fi; }

# ssh answers the session listing with FAKE_SESSIONS (session<TAB>repo lines)
# and records the host it was asked for. cmux answers workspace.list with
# FAKE_ROWS, workspace.group.list with FAKE_GROUPS, and `ssh` with a new row's
# handle, all in the shapes cmux 0.65 really prints; it records every call, one
# per line, arguments joined by '|'. FAKE_GROUP_FAIL=1 makes the group
# commands fail the way cmux does, with a message on stderr. fzf saves the picker lines it was given
# and returns FAKE_PICK. With FAKE_KEY=n it plays the n binding instead: runs
# the binding's execute-silent command and aborts, as fzf would.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$WORK/ssh-hosts"
cat > /dev/null
printf '%s' "${FAKE_SESSIONS-}"
EOF
cat > "$WORK/bin/cmux" <<'EOF'
#!/usr/bin/env bash
(IFS='|'; printf '%s\n' "$*") >> "$WORK/cmux-calls"
case "$1 ${2-}" in
    "rpc workspace.list")       printf '%s\n' "${FAKE_ROWS:-{\"workspaces\":[]}}" ;;
    "rpc workspace.group.list") printf '%s\n' "${FAKE_GROUPS:-{\"groups\":[]}}" ;;
    "ssh "*)                    printf 'OK workspace:7 surface:9\n' ;;
    "workspace-group "*)
        if [ -n "${FAKE_GROUP_FAIL-}" ]; then echo "Error: not_found: Group not found" >&2; exit 1; fi
        echo "OK workspace_group:3" ;;
esac
EOF
cat > "$WORK/bin/fzf" <<'EOF'
#!/usr/bin/env bash
cat > "$WORK/fzf-in"
printf '%s\0' "$@" > "$WORK/fzf-args"
if [ "${FAKE_KEY-}" = n ]; then
    for a in "$@"; do
        case $a in n:execute-silent\(*\)+abort)
            c=${a#n:execute-silent(}; sh -c "${c%)+abort}"; exit 130 ;;
        esac
    done
    exit 99
fi
printf '%s\n' "${FAKE_PICK-}"
EOF
chmod +x "$WORK/bin/"*

SESSIONS=$(printf 'webapp\twebapp\nzeta\tzeta\nwebapp_cmux_improvement\twebapp\nacme_report\tacme\n')

unset CMUX_BERTH_CONFIG XDG_CONFIG_HOME
export HOME="$WORK/home"; mkdir -p "$HOME"
run() {  # resets the call logs, then runs it with the stubs first on PATH
    rm -f "$WORK/cmux-calls" "$WORK/ssh-hosts"
    PATH="$WORK/bin:$PATH" FAKE_SESSIONS="$SESSIONS" CMUX_BERTH_HOST="${CMUX_BERTH_HOST-test-box}" \
        CMUX_BERTH_RENAME_DELAYS="${CMUX_BERTH_RENAME_DELAYS-}" \
        bash "$SRC" "$@" > "$WORK/out" 2>&1
    echo $? > "$WORK/rc"
}
# The calls made after it returns: the late renames run in the background.
late() {  # waits up to 5s for $1 rename calls, then prints them
    for _ in $(seq 50); do
        [ "$(calls | grep -c '^workspace|rename|')" -ge "$1" ] && break
        sleep 0.1
    done
    grep '^workspace|rename|' "$WORK/cmux-calls" 2>/dev/null
}
calls() { cat "$WORK/cmux-calls" 2>/dev/null; }
rc() { cat "$WORK/rc"; }

ATTACH="tmux attach-session -t '=webapp_cmux_improvement'"

# --- no group yet: open the row, then create the group from it ---------------
run webapp_cmux_improvement
check "new session, new group: exit 0" "$(rc)" "0"
check "new session, new group: calls" "$(calls)" "rpc|workspace.list
rpc|workspace.group.list
ssh|test-box|--name|cmux_improvement|--command|$ATTACH
workspace-group|create|--name|webapp|--idempotency-key|cmux-berth:webapp
workspace-group|add|--group|workspace_group:3|--workspace|workspace:7"
check "the host comes from CMUX_BERTH_HOST" "$(cat "$WORK/ssh-hosts")" "test-box"

# --- the box's placeholder name can land after cmux's own rename -------------
CMUX_BERTH_RENAME_DELAYS='0 0' run webapp_cmux_improvement
check "new row: name sent again after the row opens" "$(late 2)" \
    "workspace|rename|--workspace|workspace:7|--title|cmux_improvement
workspace|rename|--workspace|workspace:7|--title|cmux_improvement"

# --- group already made by cmux-berth: add the new row to it -------------------------
export FAKE_GROUPS='{"groups":[{"id":"G-OTHER","name":"acme","member_workspace_ids":[]},{"id":"G1","name":"renamed by hand","external_id":"cmux-berth:webapp","member_workspace_ids":[]}]}'
run webapp_cmux_improvement
check "group found by its cmux-berth key, even after a rename" "$(calls | tail -1)" \
    "workspace-group|add|--group|G1|--workspace|workspace:7"

# --- group made by hand with the repo name: adopt it -------------------------
export FAKE_GROUPS='{"groups":[{"id":"G2","name":"webapp","member_workspace_ids":[]}]}'
run webapp_cmux_improvement
check "hand-made group found by name" "$(calls | tail -1)" \
    "workspace-group|add|--group|G2|--workspace|workspace:7"

# --- the row already exists in that group: select it, open nothing -----------
export FAKE_ROWS='{"workspaces":[{"id":"W-ELSEWHERE","ref":"workspace:2","title":"cmux_improvement"},{"id":"W1","ref":"workspace:3","title":"cmux_improvement"}]}'
export FAKE_GROUPS='{"groups":[{"id":"G2","name":"webapp","member_workspace_ids":["W1"]},{"id":"G-OTHER","name":"acme","member_workspace_ids":["W-ELSEWHERE"]}]}'
run webapp_cmux_improvement
check "existing row selected, not reopened" "$(calls)" 'rpc|workspace.list
rpc|workspace.group.list
rpc|workspace.select|{"workspace_id":"W1"}'
CMUX_BERTH_RENAME_DELAYS=0 run webapp_cmux_improvement
check "existing row: no late rename" "$(sleep 0.3; late 0)" ""

# --- same title in another group is a different row --------------------------
export FAKE_ROWS='{"workspaces":[{"id":"W-ELSEWHERE","ref":"workspace:2","title":"cmux_improvement"}]}'
export FAKE_GROUPS='{"groups":[{"id":"G2","name":"webapp","member_workspace_ids":[]},{"id":"G-OTHER","name":"acme","member_workspace_ids":["W-ELSEWHERE"]}]}'
run webapp_cmux_improvement
check "a same-titled row in another group is not reused" "$(calls | grep -c '^ssh|')" "1"
unset FAKE_ROWS FAKE_GROUPS

# --- a failed group step is reported, not swallowed --------------------------
FAKE_GROUP_FAIL=1 run webapp_cmux_improvement
check "group failure: exit 1" "$(rc)" "1"
check "group failure: cmux's message reaches the terminal" "$(grep -c 'Group not found' "$WORK/out")" "1"

# --- a main checkout session is named main ----------------------------------
run webapp
check "main checkout row is named main" "$(calls | grep '^ssh|' | cut -d'|' -f1-4)" "ssh|test-box|--name|main"

# --- picker -----------------------------------------------------------------
FAKE_PICK=$(printf 'acme\tacme_report') run
check "picker: chosen session opens" "$(calls | grep '^ssh|' | cut -d'|' -f1-4)" "ssh|test-box|--name|report"
FAKE_PICK='' run
check "picker: cancel exits nonzero" "$(rc)" "1"

# What the picker shows. Each line is a colored display field, a tab, then the
# plain session name cx reads back. The display field is the repo padded to the
# longest repo name, then the session.
ESC=$(printf '\033')
display() { sed 1d "$WORK/fzf-in" | cut -f1 | sed "s/$ESC\[[0-9;]*m//g"; }
check "picker: new shell first, then by repo and session" "$(cut -f2 "$WORK/fzf-in" | tr '\n' ' ')" \
    ":new acme_report webapp webapp_cmux_improvement zeta "
check "picker: session column lines up" "$(display | awk '{match($0, /  +[^ ]/); print RSTART + RLENGTH - 1}' | sort -u)" "9"
# The color codes in front of the repo and the session, per line.
colors() { sed 1d "$WORK/fzf-in" | cut -f1 | sed "s/[^$ESC]*$ESC\(\[[0-9;]*m\)[^$ESC]*$ESC\(\[[0-9;]*m\).*/\1 \2/"; }
check "picker: both columns colored on every line" \
    "$(colors | grep -c '^\[[0-9;]*m \[[0-9;]*m$')" "4"
check "picker: a repo keeps one color" "$(colors | sed -n 2,3p | sort -u | wc -l | tr -d ' ')" "1"
check "picker: repos get different colors" "$(colors | sort -u | wc -l | tr -d ' ')" "3"
check "picker: the two columns differ in shade" \
    "$(colors | awk '$1 == $2' | wc -l | tr -d ' ')" "0"
check "picker: color ends before the session name" "$(cut -f2- "$WORK/fzf-in" | grep -c "$ESC")" "0"

# --- a new shell from the picker: its entry, or the n key ---------------------
FAKE_PICK=$(printf '+ new shell in ~\t:new') run
check "picker: new-shell entry opens a plain shell" "$(calls)" "ssh|test-box"
FAKE_KEY=n run
check "picker: n opens a plain shell" "$(calls)" "ssh|test-box"
check "picker: n exits 0" "$(rc)" "0"
run ':new'
check "':new' is not a session name on the command line" "$(rc)" "1"

# esc leaves filter mode back to the list, and quits from the list. fzf runs
# the transform through a shell with FZF_PROMPT set; this does the same.
esc=$(FAKE_KEY=x run >/dev/null; tr '\0' '\n' < "$WORK/fzf-args" | sed -n 's/^esc:transform://p')
check "esc in filter mode returns to the list" \
    "$(FZF_PROMPT='filter> ' sh -c "$esc" | grep -c 'disable-search+rebind(j,k,q,n,/)')" "1"
check "esc on the list quits" "$(FZF_PROMPT='session on test-box> ' sh -c "$esc")" "abort"
check "picker: cancel opens nothing" "$(calls | grep -c '^ssh|')" "0"

# --- refusals ----------------------------------------------------------------
run no_such_session
check "unknown session: exit 1" "$(rc)" "1"
check "unknown session: opens nothing" "$(calls | grep -c '^ssh|')" "0"
run 'bad;name'
check "unsafe session name refused" "$(rc)" "1"
check "unsafe session name never reaches the box" "$(cat "$WORK/ssh-hosts" 2>/dev/null)" ""

# --- a fresh shell in ~ on the box, for setting up a new worktree ------------
CMUX_BERTH_RENAME_DELAYS=0 run -n scratch
check "new shell: exit 0" "$(rc)" "0"
check "new shell: no tmux attach, no group, no listing" "$(calls | grep -v '^workspace|rename|')" \
    "ssh|test-box|--name|scratch"
check "new shell: never asks the box for sessions" "$(cat "$WORK/ssh-hosts" 2>/dev/null)" ""
check "new shell: name sent again" "$(late 1 | head -1)" \
    "workspace|rename|--workspace|workspace:7|--title|scratch"
CMUX_BERTH_RENAME_DELAYS=0 run --new
check "new shell, no name: cmux names it" "$(calls)" "ssh|test-box"
check "new shell, no name: no late rename" "$(sleep 0.3; late 0)" ""
run -n a b
check "new shell: one name only" "$(rc)" "1"

# --- the host ------------------------------------------------------------------
CMUX_BERTH_HOST=other-box run webapp
check "CMUX_BERTH_HOST picks the host" "$(cat "$WORK/ssh-hosts")" "other-box"
check "and reaches cmux ssh" "$(calls | grep '^ssh|' | cut -d'|' -f2)" "other-box"
run -H flag-box webapp
check "-H beats the environment" "$(cat "$WORK/ssh-hosts")" "flag-box"
mkdir -p "$HOME/.config/cmux-berth"
printf '# comment\nhost = conf-box\n' > "$HOME/.config/cmux-berth/config"
CMUX_BERTH_HOST='' run webapp
check "the config file gives the host when the environment does not" "$(cat "$WORK/ssh-hosts")" "conf-box"
rm -f "$HOME/.config/cmux-berth/config"
CMUX_BERTH_HOST='' run webapp
check "no host anywhere: exit 1" "$(rc)" "1"
check "and says how to give one" "$(grep -c 'Pass -H <host>' "$WORK/out")" "1"
check "and never reaches ssh" "$(cat "$WORK/ssh-hosts" 2>/dev/null)" ""

# --- an fzf too old for the picker ------------------------------------------------
printf '#!/bin/sh\necho "0.44.1 (debian)"\n' > "$WORK/oldfzf"; chmod +x "$WORK/oldfzf"
mkdir -p "$WORK/oldbin"; cp "$WORK/oldfzf" "$WORK/oldbin/fzf"
rm -f "$WORK/cmux-calls" "$WORK/ssh-hosts"
PATH="$WORK/oldbin:$WORK/bin:$PATH" FAKE_SESSIONS="$SESSIONS" CMUX_BERTH_HOST=test-box bash "$SRC" > "$WORK/out" 2>&1
check "an fzf older than 0.46 is refused by name" "$(grep -c 'fzf 0.46 or newer' "$WORK/out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
