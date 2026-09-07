#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

HANDLER="$ROOT/bin/omarchy-webapp-handler-teams"
DESKTOP="$ROOT/applications/Microsoft Teams Meeting.desktop"
ICON_DIR="$ROOT/applications/icons"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
tools_bin="$test_tmp/tools"
mkdir -p "$mock_bin" "$tools_bin"
ln -s /usr/bin/mkdir "$tools_bin/mkdir"
ln -s /usr/bin/mv "$tools_bin/mv"

# Record launches; do not exec a real browser or Teams client.
cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_WEBAPP_LOG"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_UWSM_LOG"
SH

chmod +x "$mock_bin"/*

CASE_DIR=
WEBAPP_LOG=
UWSM_LOG=
STATE_HOME=
HANDLER_PATH=
HANDLER_STATUS=0

begin_case() {
  local mode="$1"

  CASE_DIR=$(mktemp -d "$test_tmp/case.XXXXXX")
  WEBAPP_LOG="$CASE_DIR/webapp.log"
  UWSM_LOG="$CASE_DIR/uwsm.log"
  STATE_HOME="$CASE_DIR/state"
  mkdir -p "$STATE_HOME" "$CASE_DIR/home"
  : >"$WEBAPP_LOG"
  : >"$UWSM_LOG"

  HANDLER_PATH="$mock_bin:$ROOT/bin:$tools_bin"
  if [[ $mode == "native" ]]; then
    mkdir -p "$CASE_DIR/native-bin"
    printf '%s\n' '#!/bin/bash' 'exit 0' >"$CASE_DIR/native-bin/teams-for-linux"
    chmod +x "$CASE_DIR/native-bin/teams-for-linux"
    HANDLER_PATH="$CASE_DIR/native-bin:$HANDLER_PATH"
  fi
}

run_handler() {
  HANDLER_STATUS=0
  HOME="$CASE_DIR/home" \
    PATH="$HANDLER_PATH" \
    XDG_STATE_HOME="$STATE_HOME" \
    OMARCHY_TEST_WEBAPP_LOG="$WEBAPP_LOG" \
    OMARCHY_TEST_UWSM_LOG="$UWSM_LOG" \
    "$HANDLER" "$@" || HANDLER_STATUS=$?
}

assert_file_content() {
  local file="$1"
  local desc="$2"
  local expected_file="$CASE_DIR/assert-expected"

  if (( $# >= 3 )); then
    printf '%s\n' "$3" >"$expected_file"
  else
    : >"$expected_file"
  fi

  if ! diff -u "$expected_file" "$file" >/dev/null; then
    diff -u "$expected_file" "$file" >&2 || true
    fail "$desc"
  fi
}

assert_webapp() {
  local expected="$1"
  local desc="$2"

  (( HANDLER_STATUS == 0 )) || fail "$desc (exit $HANDLER_STATUS)"
  assert_file_content "$WEBAPP_LOG" "$desc" "$expected"
  assert_file_content "$UWSM_LOG" "$desc does not launch teams-for-linux"
  pass "$desc"
}

assert_native() {
  local expected="$1"
  local desc="$2"

  (( HANDLER_STATUS == 0 )) || fail "$desc (exit $HANDLER_STATUS)"
  assert_file_content "$UWSM_LOG" "$desc" "$expected"
  assert_file_content "$WEBAPP_LOG" "$desc does not launch a web app"
  pass "$desc"
}

assert_throttled() {
  local desc="$1"

  (( HANDLER_STATUS == 0 )) || fail "$desc (exit $HANDLER_STATUS)"
  assert_file_content "$UWSM_LOG" "$desc does not launch teams-for-linux"
  pass "$desc"
}

[[ -x $HANDLER ]] || fail "omarchy-webapp-handler-teams is executable"

# A5.1 meeting shapes. Hosted, host-less, slash variants, : and %3a / %3A ids.
meeting_urls=(
  'msteams://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams://teams.live.com/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams://teams.cloud.microsoft/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams://l/meetup-join/19:meeting_abc@thread.v2'
  'msteams:teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams:///teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams:l/meetup-join/19:meeting_abc@thread.v2'
  'msteams:///l/meetup-join/19:meeting_abc@thread.v2'
  'msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2'
  'msteams://teams.microsoft.com/l/meetup-join/19%3Ameeting_abc@thread.v2'
)

meeting_https=(
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.live.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.cloud.microsoft/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2?omarchyWebapp=1'
  'https://teams.microsoft.com/l/meetup-join/19%3Ameeting_abc@thread.v2?omarchyWebapp=1'
)

for i in "${!meeting_urls[@]}"; do
  url="${meeting_urls[$i]}"
  https="${meeting_https[$i]}"

  begin_case native
  run_handler "$url"
  assert_native "-- teams-for-linux --gtk-version=3 $url" \
    "native forwards meeting $url unchanged"

  begin_case web
  run_handler "$url"
  assert_webapp "$https" \
    "web app opens meeting $url with omarchyWebapp marker"
done

# Marker join: & vs ? , placed before any #fragment.
begin_case web
run_handler 'msteams://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?context=%7B%22Tid%22%3A%22t%22%7D'
assert_webapp \
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?context=%7B%22Tid%22%3A%22t%22%7D&omarchyWebapp=1' \
  "marker joins with & when a query exists"

begin_case web
run_handler 'msteams://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2#/join'
assert_webapp \
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1#/join' \
  "marker joins with ? and sits before the fragment"

begin_case web
run_handler 'msteams://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?context=abc#/join'
assert_webapp \
  'https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?context=abc&omarchyWebapp=1#/join' \
  "marker joins with & and sits before the fragment"

# A5.2 / look-alike: native forwards any msteams: URL; web app opens Teams home.
home_url='https://teams.microsoft.com/'
non_meetings=(
  'msteams://teams.microsoft.com.evil.test/l/meetup-join/19:meeting_abc@thread.v2'
  'msteams://teams.microsoft.com/l/chat/19:thread@thread.v2'
  'msteams://teams.microsoft.com/meet/abc123'
)

for url in "${non_meetings[@]}"; do
  begin_case native
  run_handler "$url"
  assert_native "-- teams-for-linux --gtk-version=3 $url" \
    "native forwards non-meeting $url unchanged"

  begin_case web
  run_handler "$url"
  assert_webapp "$home_url" \
    "web app opens Teams home for non-meeting $url"
done

begin_case native
run_handler
assert_native "-- teams-for-linux --gtk-version=3" \
  "native with no argument opens teams-for-linux with no URL"

begin_case web
run_handler
assert_webapp "$home_url" \
  "web app with no argument opens Teams home"

begin_case native
run_handler 'https://example.com/'
assert_native "-- teams-for-linux --gtk-version=3" \
  "native with a non-msteams argument opens teams-for-linux with no URL"

begin_case web
run_handler 'https://example.com/'
assert_webapp "$home_url" \
  "web app with a non-msteams argument opens Teams home"

# Throttle (web-app path only). Fresh XDG_STATE_HOME per begin_case.
meeting_plain='msteams://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2'
meeting_encoded='msteams://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2'
meeting_other='msteams://teams.microsoft.com/l/meetup-join/19:meeting_other@thread.v2'
web_plain='https://teams.microsoft.com/l/meetup-join/19:meeting_abc@thread.v2?omarchyWebapp=1'
web_other='https://teams.microsoft.com/l/meetup-join/19:meeting_other@thread.v2?omarchyWebapp=1'
stamp_id='l/meetup-join/19:meeting_abc@thread.v2'

begin_case web
run_handler "$meeting_plain"
assert_webapp "$web_plain" "throttle first open launches the meeting"
run_handler "$meeting_plain"
assert_file_content "$WEBAPP_LOG" "throttle second open does not launch again" "$web_plain"
assert_throttled "same meeting id twice in-window opens once"

begin_case web
mkdir -p "$STATE_HOME/omarchy"
now=$(printf '%(%s)T' -1)
printf '%s %s\n' "$stamp_id" "$((now - 20))" >"$STATE_HOME/omarchy/teams-join-last"
run_handler "$meeting_plain"
assert_webapp "$web_plain" "same id after the throttle window opens again"

begin_case web
run_handler "$meeting_plain"
run_handler "$meeting_other"
assert_file_content "$WEBAPP_LOG" "different id launches twice" "$web_plain"$'\n'"$web_other"
assert_file_content "$UWSM_LOG" "different id does not launch teams-for-linux"
pass "a different meeting id always opens"

begin_case web
run_handler "$meeting_encoded"
run_handler "$meeting_plain"
assert_file_content "$WEBAPP_LOG" "encoded and decoded ids share one launch" \
  'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2?omarchyWebapp=1'
assert_throttled "two encodings of one id count as the same meeting"

begin_case web
mkdir -p "$STATE_HOME/omarchy"
: >"$STATE_HOME/omarchy/teams-join-last"
run_handler "$meeting_plain"
assert_webapp "$web_plain" "an empty throttle stamp opens"

begin_case web
mkdir -p "$STATE_HOME/omarchy"
printf '%s\n' "$stamp_id" >"$STATE_HOME/omarchy/teams-join-last"
run_handler "$meeting_plain"
assert_webapp "$web_plain" "a one-field throttle stamp opens"

# .desktop claims the msteams scheme.
[[ -f $DESKTOP ]] || fail "Microsoft Teams Meeting.desktop exists"

grep -Fxq 'MimeType=x-scheme-handler/msteams;' "$DESKTOP" ||
  fail "desktop MimeType is x-scheme-handler/msteams;"
pass "desktop MimeType is x-scheme-handler/msteams;"

grep -Fxq 'Exec=omarchy-webapp-handler-teams %u' "$DESKTOP" ||
  fail "desktop Exec is omarchy-webapp-handler-teams %u"
pass "desktop Exec is omarchy-webapp-handler-teams %u"

grep -Fxq 'NoDisplay=true' "$DESKTOP" ||
  fail "desktop sets NoDisplay=true"
pass "desktop sets NoDisplay=true"

icon_line=$(grep -E '^Icon=' "$DESKTOP" || true)
[[ -n $icon_line ]] || fail "desktop sets Icon"
icon_name="${icon_line#Icon=}"

found_icon=""
shopt -s nullglob
for png in "$ICON_DIR"/*.png; do
  base=$(basename "$png" .png)
  dashed=$(printf '%s' "$base" | tr '[:upper:] ' '[:lower:]-')
  if [[ $dashed == "$icon_name" ]]; then
    found_icon=$png
    break
  fi
done
shopt -u nullglob

[[ -n $found_icon ]] ||
  fail "Icon=$icon_name matches a PNG in applications/icons" "no lowercase-dashed match for $icon_name"

magic=$(head -c 8 "$found_icon" | od -An -tx1 | tr -d ' \n')
[[ $magic == "89504e470d0a1a0a" ]] ||
  fail "Icon PNG is a valid PNG" "$found_icon magic=$magic"

pass "desktop Icon=$icon_name matches $(basename "$found_icon")"
