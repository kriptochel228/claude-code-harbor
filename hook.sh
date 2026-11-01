#!/usr/bin/env bash
# Claude Code Harbor hook.
# Each Claude Code event becomes ONE tiny line like:
#   {"e":"PreToolUse","s":"1d218b4c","p":"my-app","t":"Bash","ts":1730000000}
# It never sends prompts, code, commands, file contents or file paths: only the
# event name, a short session id, the project FOLDER name and the tool name.
# Runs as a shell command, so it uses zero model tokens.
D="$HOME/.claude/harbor"
IN=$(cat)
f(){ printf '%s' "$IN" | grep -o "\"$1\":\"[^\"]*\"" | head -1 | sed "s/^\"$1\":\"//; s/\"\$//"; }
E=$(f hook_event_name); [ -z "$E" ] && exit 0
S=$(f session_id); S=${S:0:8}
C=$(f cwd); P=${C##*/}; P=${P##*\\}
[ -n "$HARBOR_HIDE_PROJECT" ] && P="project"
T=$(f tool_name); A=$(f agent_id); A=${A:0:6}
U=""; SA=""; X=""
case "$T" in Agent|Task) U=$(f tool_use_id); U=${U: -6}; SA=$(f subagent_type);; esac
[ "$E" = "Notification" ] && X=$(f notification_type)
L="{\"e\":\"$E\",\"s\":\"$S\",\"p\":\"$P\",\"ts\":$(date +%s)"
[ -n "$T" ] && L="$L,\"t\":\"$T\""
[ -n "$A" ] && L="$L,\"a\":\"$A\""
[ -n "$U" ] && L="$L,\"u\":\"$U\""
[ -n "$SA" ] && L="$L,\"sa\":\"$SA\""
[ -n "$X" ] && L="$L,\"x\":\"$X\""
L="$L}"
mkdir -p "$D"; printf '%s\n' "$L" >> "$D/queue"
# Batch to stay far below ntfy.sh rate limits: send right away for the events
# that matter, otherwise at most once every 10 seconds.
NOW=$(date +%s); LAST=$(cat "$D/last" 2>/dev/null || echo 0)
case "$E" in SessionStart|UserPromptSubmit|Notification|Stop|SessionEnd|SubagentStop) GO=1;; *) GO=0;; esac
[ "$T" = "Agent" ] || [ "$T" = "Task" ] && GO=1
[ $((NOW-LAST)) -ge 10 ] && GO=1
[ "$GO" = 1 ] || exit 0
echo "$NOW" > "$D/last"
B="$D/batch.$$"; mv "$D/queue" "$B" 2>/dev/null || exit 0
TOPIC=$(cat "$D/topic" 2>/dev/null)
URL="${HARBOR_URL:-https://ntfy.sh/$TOPIC}"
( curl -s -m 5 --data-binary @"$B" "$URL" >/dev/null 2>&1; rm -f "$B" ) >/dev/null 2>&1 &
exit 0
