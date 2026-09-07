#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration=$(grep -rl 'Add Microsoft Teams meeting handler and Chromium join extension' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "teams-join migration exists"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/update-desktop-database" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$UPDATE_DESKTOP_CALLS"
STUB
chmod +x "$stub_bin/update-desktop-database"

home="$test_dir/home"
desktop_src="$ROOT/applications/Microsoft Teams Meeting.desktop"
desktop_dest="$home/.local/share/applications/Microsoft Teams Meeting.desktop"
flags_ext="$ROOT/default/chromium/extensions/teams-join"

browsers=(
  chromium
  chrome
  google-chrome
  brave
  brave-beta
  brave-nightly
  brave-origin-beta
  microsoft-edge-stable
  brave-origin
)

mkdir -p "$home/.config"
for conf in "${browsers[@]}"; do
  printf '%s\n' \
    '--ozone-platform=wayland' \
    '--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url' \
    >"$home/.config/${conf}-flags.conf"
done

export UPDATE_DESKTOP_CALLS="$test_dir/update-desktop-calls"
: >"$UPDATE_DESKTOP_CALLS"

run_migration() {
  : >"$UPDATE_DESKTOP_CALLS"
  HOME="$home" PATH="$stub_bin:$PATH" OMARCHY_PATH="$ROOT" \
    bash -euo pipefail "$migration" >"$test_dir/migration-out"
}

assert_one_flags_entry() {
  local conf file entries
  for conf in "${browsers[@]}"; do
    file="$home/.config/${conf}-flags.conf"
    entries=$(grep -o "extensions/teams-join" "$file" | wc -l || :)
    (( entries == 1 )) ||
      fail "$conf-flags.conf has one teams-join entry" "$conf entries=$entries"
  done
}

assert_one_desktop() {
  [[ -f $desktop_dest ]] || fail "migration copies Microsoft Teams Meeting.desktop"
  cmp -s "$desktop_src" "$desktop_dest" ||
    fail "copied .desktop matches the shipped file"
  local copies
  copies=$(find "$home/.local/share/applications" -name 'Microsoft Teams Meeting.desktop' | wc -l)
  (( copies == 1 )) || fail "migration leaves one .desktop" "copies=$copies"
}

assert_one_update_desktop_database() {
  local calls
  calls=$(wc -l <"$UPDATE_DESKTOP_CALLS")
  (( calls == 1 )) ||
    fail "migration runs update-desktop-database once per run" "calls=$calls"
  grep -Fxq "$home/.local/share/applications" "$UPDATE_DESKTOP_CALLS" ||
    fail "update-desktop-database is called on ~/.local/share/applications" \
      "$(cat "$UPDATE_DESKTOP_CALLS")"
}

run_migration

assert_one_flags_entry
pass "first run writes one teams-join flags entry per browser"

assert_one_desktop
pass "first run copies one Microsoft Teams Meeting.desktop"

assert_one_update_desktop_database
pass "first run calls update-desktop-database once"

grep -q "extensions/teams-join" "$home/.config/brave-origin-flags.conf" ||
  fail "first run adds teams-join to brave-origin-flags.conf"
pass "first run writes the brave-origin flags entry"

grep -qi 'restart Chromium/Brave to load the Teams extension' "$test_dir/migration-out" ||
  fail "first run tells the user to restart Chromium/Brave" "$(cat "$test_dir/migration-out")"
pass "first run prints the Chromium/Brave restart note"

run_migration

assert_one_flags_entry
pass "second run leaves one teams-join flags entry per browser"

assert_one_desktop
pass "second run leaves one Microsoft Teams Meeting.desktop"

assert_one_update_desktop_database
pass "second run calls update-desktop-database once"

grep -q "extensions/teams-join" "$home/.config/brave-origin-flags.conf" ||
  fail "second run keeps the brave-origin flags entry"
entries=$(grep -o "extensions/teams-join" "$home/.config/brave-origin-flags.conf" | wc -l || :)
(( entries == 1 )) || fail "brave-origin-flags.conf is not duplicated on rerun" "entries=$entries"
pass "second run keeps one brave-origin flags entry"
