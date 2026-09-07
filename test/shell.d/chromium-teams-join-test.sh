#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command node

EXT_DIR="$ROOT/default/chromium/extensions/teams-join"
MANIFEST="$EXT_DIR/manifest.json"
FLAGS="$ROOT/config/chromium-flags.conf"

HOSTS=(
  "https://teams.microsoft.com/*"
  "https://teams.cloud.microsoft/*"
  "https://teams.live.com/*"
)

[[ -f $MANIFEST ]] || fail "teams-join manifest exists"

jq -e --argjson hosts "$(printf '%s\n' "${HOSTS[@]}" | jq -R . | jq -s .)" '
  .manifest_version == 3
  and .content_scripts[0].matches == $hosts
  and .host_permissions == $hosts
  and .content_scripts[0].run_at == "document_start"
  and .content_scripts[0].js == ["content.js"]
  and (has("background") | not)
  and ((.permissions // []) | index("webNavigation") | not)
  and ((.permissions // []) | index("tabs") | not)
  and ((.optional_permissions // []) | index("webNavigation") | not)
  and ((.optional_permissions // []) | index("tabs") | not)
  and (.browser_specific_settings.gecko.id | type == "string" and length > 0)
' "$MANIFEST" >/dev/null || fail "teams-join manifest is MV3 content-script only"

matches_json=$(jq -c '.content_scripts[0].matches' "$MANIFEST")
echo "$matches_json" | jq -e 'index("http://teams.microsoft.com/*") or index("<all_urls>")' >/dev/null &&
  fail "teams-join matches are https hosts only, no http:// or <all_urls>" "$matches_json"

hosts_json=$(jq -c '.host_permissions' "$MANIFEST")
echo "$hosts_json" | jq -e 'index("http://teams.microsoft.com/*") or index("<all_urls>")' >/dev/null &&
  fail "teams-join host_permissions are https hosts only, no http:// or <all_urls>" "$hosts_json"

pass "teams-join manifest is MV3 content-script only for the three https hosts"

load_line=$(grep '^--load-extension=' "$FLAGS" || true)
[[ -n $load_line ]] || fail "chromium-flags.conf has a --load-extension= line"

[[ $load_line == *extensions/teams-join* ]] ||
  fail "chromium-flags.conf loads teams-join" "$load_line"

shopt -s nullglob
for manifest in "$ROOT/default/chromium/extensions"/*/manifest.json; do
  ext_id=$(basename "$(dirname "$manifest")")
  [[ $load_line == *"/extensions/$ext_id"* ]] ||
    fail "chromium-flags.conf loads $ext_id" "$load_line"
done
shopt -u nullglob

IFS=',' read -ra flag_paths <<< "${load_line#--load-extension=}"
for flag_path in "${flag_paths[@]}"; do
  ext_id=$(basename "$flag_path")
  [[ -f $ROOT/default/chromium/extensions/$ext_id/manifest.json ]] ||
    fail "chromium-flags.conf lists $ext_id but the extension is missing"
done

pass "chromium-flags.conf --load-extension= matches the shipped extension dirs"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const contentPath = path.join(root, 'default/chromium/extensions/teams-join/content.js')
let contentJs
try {
  contentJs = fs.readFileSync(contentPath, 'utf8')
} catch (error) {
  fail('content.js exists', String(error))
}

function runScript(href, options = {}) {
  const store = options.store || new Map()
  const state = {
    href,
    stopCalls: 0,
    standalone: options.standalone === true,
    lastMatchMediaQuery: null,
  }
  const sandbox = {
    URL,
    sessionStorage: {
      getItem(key) {
        return store.has(key) ? store.get(key) : null
      },
      setItem(key, value) {
        store.set(key, String(value))
      },
    },
    window: {},
  }
  sandbox.window.location = {
    get href() {
      return state.href
    },
    set href(value) {
      state.href = value
    },
  }
  sandbox.window.matchMedia = (query) => {
    state.lastMatchMediaQuery = query
    return { matches: state.standalone }
  }
  sandbox.window.stop = () => {
    state.stopCalls += 1
  }
  vm.runInNewContext(contentJs, sandbox, { filename: 'content.js' })
  return { state, store }
}

const hosts = [
  'teams.microsoft.com',
  'teams.cloud.microsoft',
  'teams.live.com',
]
const context = 'context=%7B%22Tid%22%3A%22t%22%7D'
const meetingColon = '/l/meetup-join/19:meeting_abc@thread.v2'
const meetingEncoded = '/l/meetup-join/19%3ameeting_abc@thread.v2'
const expectedColon = `msteams://teams.microsoft.com${meetingColon}`
const expectedEncoded = `msteams://teams.microsoft.com${meetingEncoded}`
const expectedWithContext = `msteams://teams.microsoft.com${meetingColon}?${context}`

function assertFires(href, expected, description) {
  const { state } = runScript(href)
  assertEqual(state.href, expected, `${description} rewrites to msteams://teams.microsoft.com`)
  assertEqual(state.stopCalls, 1, `${description} calls window.stop after a fire`)
}

function launcherHref(pageHost, inner, extra = {}) {
  const url = new URL(`https://${pageHost}/dl/launcher/launcher.html`)
  url.searchParams.set('url', inner)
  for (const [key, value] of Object.entries(extra)) {
    url.searchParams.set(key, value)
  }
  return url.href
}

for (const host of hosts) {
  assertFires(
    `https://${host}${meetingColon}`,
    expectedColon,
    `${host} colon meeting path`
  )
  assertFires(
    `https://${host}${meetingEncoded}`,
    expectedEncoded,
    `${host} %3a meeting path`
  )
  assertFires(
    `https://${host}/v2/?meetingjoin=true#${meetingColon}?${context}`,
    expectedWithContext,
    `${host} v2 fragment`
  )
  assertFires(
    launcherHref(host, `${meetingColon}?${context}`),
    expectedWithContext,
    `${host} single-encoded context in url=`
  )
  assertFires(
    launcherHref(
      host,
      `${meetingColon}?deeplinkId=abc-123&launchAgent=web&${context}&anon=true&enablemcas=1&suppressPrompt=true`
    ),
    expectedWithContext,
    `${host} deeplinkId= before context=`
  )
}

function assertStandDownAndLatch(href, description) {
  const store = new Map()
  const first = runScript(href, { store })
  assertEqual(first.state.href, href, `${description} stands down`)
  assertEqual(first.state.stopCalls, 0, `${description} does not call window.stop`)
  assert(store.size > 0, `${description} latches the tab`)

  const hop = `https://teams.microsoft.com/v2/?meetingjoin=true#${meetingColon}`
  const second = runScript(hop, { store })
  assertEqual(second.state.href, hop, `${description} latches a later marker-less /v2/ hop`)
  assertEqual(second.state.stopCalls, 0, `${description} /v2/ hop does not fire`)
}

assertStandDownAndLatch(
  `https://teams.microsoft.com${meetingColon}?omarchyWebapp=1`,
  'omarchyWebapp=1'
)

const encodedMarkerHref = launcherHref(
  'teams.microsoft.com',
  `${meetingColon}?omarchyWebapp=1`
)
assert(
  encodedMarkerHref.includes('omarchyWebapp%3D1'),
  'encoded marker href contains omarchyWebapp%3D1',
  encodedMarkerHref
)
assertStandDownAndLatch(encodedMarkerHref, 'omarchyWebapp%3D1')

{
  const href = `https://teams.microsoft.com${meetingColon}`
  const { state } = runScript(href, { standalone: true })
  assertEqual(state.href, href, 'display-mode: standalone yields no fire')
  assertEqual(state.stopCalls, 0, 'display-mode: standalone does not call window.stop')
  assertEqual(
    state.lastMatchMediaQuery,
    '(display-mode: standalone)',
    'standalone guard queries display-mode: standalone'
  )
}

{
  const href = 'https://teams.microsoft.com/l/chat/19:thread@thread.v2'
  const { state, store } = runScript(href)
  assertEqual(state.href, href, 'non-meeting URL does not fire')
  assertEqual(state.stopCalls, 0, 'non-meeting URL does not call window.stop')
  assertEqual(store.size, 0, 'non-meeting URL does not latch')
}

{
  const href = `https://teams.microsoft.com${meetingColon}`
  const store = new Map()
  const first = runScript(href, { store })
  assertEqual(first.state.href, expectedColon, 'first visit in a tab fires')
  assertEqual(first.state.stopCalls, 1, 'first visit in a tab calls window.stop')

  const second = runScript(href, { store })
  assertEqual(second.state.href, href, 'repeat in the same tab does not fire')
  assertEqual(second.state.stopCalls, 0, 'repeat in the same tab does not call window.stop')
}

{
  const meetingA = `https://teams.microsoft.com${meetingColon}`
  const meetingBPath = '/l/meetup-join/19:meeting_xyz@thread.v2'
  const meetingB = `https://teams.microsoft.com${meetingBPath}`
  const expectedB = `msteams://teams.microsoft.com${meetingBPath}`
  const store = new Map()

  const first = runScript(meetingA, { store })
  assertEqual(first.state.href, expectedColon, 'meeting A in a shared store fires')
  assertEqual(first.state.stopCalls, 1, 'meeting A in a shared store calls window.stop')

  const second = runScript(meetingB, { store })
  assertEqual(second.state.href, expectedB, 'a different meeting in the same tab still fires')
  assertEqual(second.state.stopCalls, 1, 'a different meeting in the same tab calls window.stop')

  const keys = [...store.keys()].sort()
  assertDeepEqual(
    keys,
    [
      'teamsjoin:/l/meetup-join/19:meeting_abc@thread.v2',
      'teamsjoin:/l/meetup-join/19:meeting_xyz@thread.v2',
    ].sort(),
    'the store holds two distinct teamsjoin: keys'
  )
}
JS
