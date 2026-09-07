# Teams meeting links open the Teams app on Omarchy

Tier: Full. Combined spec and plan. Rebuilt 2026-09-07 after the earlier scratchpad draft
(drafts 1–17) was lost with a cleaned session directory. This rebuild folds in the Phase 0
spike results, which changed the core hook from `webNavigation` to a content script.

## Problem

On Windows and macOS, clicking a Teams meeting link in a calendar hands the meeting to the
Teams app. On Omarchy the link opens in a browser tab and stays there.

Zoom already works the app way on Omarchy: its join page fires `zoommtg://`, Omarchy claims
that scheme with `applications/Zoom.desktop`, and `bin/omarchy-webapp-handler-zoom` reopens
the meeting in a Chromium app window.

Teams cannot copy that pattern as-is. Verified with Playwright, 2026-09-06:

- Microsoft's join page decides in page JavaScript, from the browser's user agent, whether
  to fire `msteams:`. It fires for Windows and macOS agents only.
- With any Linux agent it never fires the scheme; it goes to the web client at
  `teams.microsoft.com/light-meetings/launch`.
- The decision is client-side; spoofing the HTTP header alone does not change it.

So on Linux the browser itself has to turn the join link into an `msteams:` URL. Once the
scheme fires, the rest is the Zoom pattern. Doing that rewrite is a small browser extension.

The pending upstream PR basecamp/omarchy#10367 (Install > Service > Microsoft) installs a
plain Teams web app. This work does not depend on it and does not change it.

## Requirements

1. Clicking a Teams meeting link (`https://<host>/l/meetup-join/19:...`, or the `19%3a`
   form, on `teams.microsoft.com`, `teams.cloud.microsoft`, or `teams.live.com`) in a
   supported browser opens the meeting in the Teams app instead of a browser tab. No extra
   click beyond the calendar link; at most a one-time browser "open msteams?" allow.
2. "The Teams app" is `teams-for-linux` when installed, otherwise an Omarchy web-app window
   on the meeting. No configuration beyond installing `teams-for-linux`.
3. Supported browsers: Chromium-based browsers Omarchy manages through `*-flags.conf`, and
   Zen. Firefox proper is out of scope (see Constraints). Google Chrome 137+ ignores
   `--load-extension` in branded builds, a gap every Omarchy extension shares; Chrome is
   not a target.
4. Existing installs get everything through one migration. New installs get it through
   `omarchy-finalize-user` and the browser install path, the same way `copy-url`, `yt-dlp`,
   and `whatsapp-slim` do. A browser installed after this ships needs nothing more: the
   installer copies the flags file and writes the Zen policy on every install, and the
   handler checks for `teams-for-linux` at run time.
5. A non-meeting `msteams:` URL (chat, team, `/meet/<id>` deep links, which Teams web and
   Outlook emit) reaches `teams-for-linux` unchanged when it is installed, so nothing that
   works with the native client today stops working. Without it, A5.2 applies.
6. A machine with neither Teams app installed must still open the meeting, in a web-app
   window. The handler for that ships with Omarchy.

## Acceptance criteria

- A1. In Chromium with Omarchy flags, a meeting link opens the meeting in the Teams app.
  The link's browser tab does not show the meeting. No click beyond the calendar link.
- A2. Same in Zen.
- A3. With `teams-for-linux` absent and a signed-in Teams web session, the web-app window
  ends on the meeting join screen. Without a session it ends on the Microsoft sign-in page.
  It does not stop on the Teams home page or the launcher page, and does not open a second
  window (loop guard).
- A4. With `teams-for-linux` installed, the meeting opens in it, with no `xdg-mime` setup.
- A5. Handler precedence, in order:
  1. A recognised meeting URL goes to `teams-for-linux` unchanged when installed, otherwise
     to a web-app window on the matching `https://` URL plus `omarchyWebapp=1` (joined with
     `&` when a query exists, `?` when not, placed before any fragment).
  2. Any other `msteams:` URL goes to `teams-for-linux` unchanged when installed (its own
     allow-list decides). No argument, or a non-`msteams:` argument, opens `teams-for-linux`
     with no URL. Without `teams-for-linux`, everything in this item opens a web-app window
     on `https://teams.microsoft.com/`.
- A6. `./test/all` passes, with new tests for the handler, the extension (including the
  content-script behaviour and the loop guard), the XPI, and the migration.
- A7. Running the migration twice leaves one `teams-join` entry per flags file, one copy of
  the `.desktop`, and the Zen policy installed once (two `sudo` calls on a box with no
  `/etc/zen/policies` yet, none on the second run).
- A8. The content script: injects on the three Teams hosts; finds the meeting in the
  launcher `url=` parameter, the page query, or the URL fragment; auto-navigates to the
  `msteams:` form once per meeting per tab; and stands down (no fire) when the page URL
  carries the `omarchyWebapp` marker in any form, including Microsoft's URL-encoded
  `omarchyWebapp%3D1` inside the launcher `url=` parameter.

## Constraints

- No new packages. No native messaging. Shell plus a manifest-v3 content-script extension.
  No background script and no `webNavigation` (see Design 1 and Decisions).
- Chromium extensions ship unpacked through `--load-extension`, per existing convention.
- Zen's effective `xpinstall.signatures.required` default is **true** in the build tested
  (1.22b / Firefox 155 base): `gre` `greprefs.js` sets it false, but `browser/omni.ja`
  `defaults/preferences/firefox.js` overrides it to true, and the app default wins. So the
  unsigned `force_installed` XPI will not install unless the policy sets the pref false.
  Zen's policy engine allows that pref because `MOZ_REQUIRE_SIGNING` is false
  (`Policies.sys.mjs` pushes it into `allowedPrefixes`). `policies-zen.json` sets it.
  Firefox release refuses unsigned XPIs and would retry on every start, so it must not get
  this policy; supporting Firefox proper needs Mozilla signing and is out of scope.
- Zen sets `MOZ_SYSTEM_POLICIES` and `MOZ_APP_NAME=zen`, so it reads
  `/etc/zen/policies/policies.json` first and ignores the package-owned
  `/opt/zen-browser-bin/distribution/policies.json` when the `/etc` file exists. Omarchy
  owns the `/etc` file outright (`install -m 644`, no merge). The old
  `omarchy-install-browser` wrote `/opt/zen-browser/distribution`, a path nothing reads;
  this work moves it to the `/etc` path.
- One extension source tree, used by both browser families. Firefox needs
  `browser_specific_settings.gecko.id`; Chromium ignores it. The extension is content-script
  only (no background), so the manifest-v3 vs event-page split that sank the earlier design
  does not arise. `host_permissions` for the three Teams hosts.
- Browsers prompt once before opening an external scheme. Because the script fires from
  Microsoft's own launcher page, the prompt's "always allow" is keyed to the
  `teams.microsoft.com` origin, a trusted origin, and one grant covers every meeting after.
  Not our problem to suppress.

## Non-goals

- Closing or redirecting the leftover browser tab after the handoff.
- Personal-account `teams.live.com/meet/<id>` links (a different shape, no demand yet).
- Shipping Chromium support first and Zen later. Zen is the default browser here.
- Pinning `x-scheme-handler/msteams` in `default/applications/mimeapps.list`.
- Forwarding non-meeting `msteams:` deep links to a web-app window. The native client gets
  them when installed; without it they open the app home / Teams home, not a stray meeting.
- A `webNavigation`-based hook. Phase 0 proved it never reaches a `force_installed`
  extension on Zen. Rejected.

## Security

- The content script declares `host_permissions` for the three Teams hosts only (no
  `<all_urls>`, no `tabs`, no `webNavigation`, no background). It reads meeting URLs on
  those hosts and fires `msteams:` for the real meeting shape only.
- The `msteams:` launch is fired from Microsoft's own launcher page, so the browser's
  "always allow" is keyed to `teams.microsoft.com`, not an arbitrary page or the extension.
  Only Microsoft's launcher page runs our script.
- Any page that reaches an `msteams:` URL is bounded twice: the script rewrites only the
  real meeting shape (`/l/meetup-join/19:` or `%3a`), and the handler re-validates host and
  path before deferring. A look-alike host, a stray path, or shell metacharacters never
  reach `teams-for-linux` or the web-app window as anything but a quoted argv element that
  already failed the regex; the path tail rejects whitespace.
- The `omarchyWebapp` marker guard stops the web-app window's copy of the extension from
  re-firing `msteams:` and looping. It must match the bare token `omarchyWebapp` because
  Microsoft URL-encodes `=1` to `%3D1` inside the launcher `url=` parameter. Confirmed live:
  a build that matched the literal `omarchyWebapp=1` looped.
- `/etc/zen/policies/policies.json` force-installs the extension into every Zen profile.
  Its directory is created mode 755, root-owned, never through the installer's
  `chmod a+rw` helper.

## Design

Data flow: click a meeting link in the browser, the content script on Microsoft's launcher
page rewrites the navigation to `msteams://...`, the browser hands it to the desktop
(Chromium 151 asks the `xdg-desktop-portal` `OpenURI` when the portal runs, `xdg-open`
otherwise; both resolve `x-scheme-handler/msteams` through the desktop database), the
Omarchy `.desktop` owning `msteams` runs the handler, and the handler picks `teams-for-linux`
or a web-app window.

### 1. Content script: `default/chromium/extensions/teams-join`

Manifest v3, content-script only, no background, no UI. Matches the three Teams hosts with
`host_permissions` and a `content_scripts` block at `run_at: document_start`. The script:

- Finds the meeting path `/l/meetup-join/19(:|%3a)...` in the launcher `url=` parameter, the
  page query, or the URL fragment (the Linux web client is
  `teams.microsoft.com/v2/?meetingjoin=true#/l/meetup-join/...`), trimming the launcher's
  `&anon`/`&deeplinkId`/`&launchAgent` tail, and rebuilds
  `msteams://teams.microsoft.com/l/meetup-join/...`.
- Loop guard: if the page URL contains the `omarchyWebapp` token (any form, including
  `omarchyWebapp%3D1`), it stands down and does nothing.
- Otherwise it auto-navigates the top frame to the `msteams:` form, once per meeting per tab
  (a `sessionStorage` guard keyed on the target, so the launcher→web-client hop fires once).

Core of `content.js` (validated in the Phase 0 spike):

```js
function meetingPath(str) {
  if (!str) return null;
  var m = str.match(/\/l\/meetup-join\/19(?::|%3[aA])[^#\s"'<>]*/);
  if (!m) return null;
  var path = m[0];
  var amp = path.search(/&(anon|deeplinkId|launchAgent|enablemcas|suppressPrompt)=/);
  if (amp > -1) path = path.slice(0, amp);
  return path;
}
var href = location.href;
var marker = href.indexOf("omarchyWebapp") !== -1;      // loop guard: bare token, survives encoding
var path = null;
try { var u = new URL(href); path = meetingPath(u.searchParams.get("url")) || meetingPath(href); }
catch (e) { path = meetingPath(href); }
var target = path ? ("msteams://teams.microsoft.com" + path) : null;
if (target && !marker) {
  try {
    var key = "teamsjoin:" + target;
    if (!sessionStorage.getItem(key)) { sessionStorage.setItem(key, "1"); window.location.href = target; }
  } catch (e) { window.location.href = target; }
}
```

**Why a content script and not `webNavigation`.** Phase 0 proved `webNavigation` events
never reach a `force_installed` (policy-installed) extension on Zen: the extension runs and
gets `chrome.tabs.*` events, but its primed `webNavigation` listener fails to reconnect at
startup ("listener not re-registered"), so `onBeforeNavigate` never fires. Temporary and
post-startup installs work; the ship path (policy) does not. A content script uses a
different, robust injection path and works for `force_installed` extensions on Zen
(confirmed live). The meetup-join URL 302s to the launcher and never commits as a page, so
a content script cannot catch it earlier; it catches it on the launcher page, where the
meeting is in the `url=` parameter.

**Why auto-fire and not a click.** The meeting id is only in the URL on the launcher page
for ~1–2 seconds before Microsoft forwards to `/light-meetings/launch`, which drops it
("no meeting in URL"). A button loses the race. Auto-fire at `document_start` catches it.
The user's real click on the calendar link supplies the gesture Chromium's external-launch
rule wants (Gecko prompts rather than requiring a gesture).

**Firefox packaging.** Firefox loads an XPI, not a directory. The extension directory is
zipped and committed as `default/firefox/teams-join.xpi`
(`python3 -m zipfile -c ../../../firefox/teams-join.xpi manifest.json content.js`), pinned
to its source by a test. Bump `manifest.version` on every change: Chromium reloads the
directory each start, but Zen installs the XPI once and reinstalls only on a version
increase. The manifest carries `browser_specific_settings.gecko.id`.

### 2. Scheme handler: `bin/omarchy-webapp-handler-teams`

Validates first, then forwards every `msteams:` URL to `teams-for-linux` when present (it
applies its own `msTeamsProtocols` allow-list, so the regex guards only the web-app path);
otherwise opens a web-app window on the `https://` meeting URL with the `omarchyWebapp=1`
marker. Validated in Phase 0 (both branches):

```bash
#!/bin/bash
# omarchy:summary=Open Teams meetings from browser protocol links
# omarchy:args=[url]
url="$1"; path=""
if [[ $url =~ ^msteams://teams\.(microsoft\.com|live\.com|cloud\.microsoft)/(l/meetup-join/19(:|%3[aA])[^[:space:]]*)$ ]]; then
  host="teams.${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"
elif [[ $url =~ ^msteams:/(l/meetup-join/19(:|%3[aA])[^[:space:]]*)$ ]]; then
  host="teams.microsoft.com"; path="${BASH_REMATCH[1]}"
fi
if omarchy-cmd-present teams-for-linux; then
  if [[ $url == msteams:* ]]; then exec setsid uwsm-app -- teams-for-linux --gtk-version=3 "$url"
  else exec setsid uwsm-app -- teams-for-linux --gtk-version=3; fi
fi
if [[ -n $path ]]; then
  web_url="https://$host/$path"; fragment=""
  [[ $web_url == *#* ]] && fragment="#${web_url#*#}" && web_url="${web_url%%#*}"
  [[ $web_url == *\?* ]] && web_url+="&omarchyWebapp=1" || web_url+="?omarchyWebapp=1"
  web_url+="$fragment"
else
  web_url="https://teams.microsoft.com/"
fi
exec omarchy-launch-webapp "$web_url"
```

The web-app window is whichever browser is default (`omarchy-launch-webapp` maps any
non-Chromium default, Zen included, to `chromium.desktop --app`), so it loads the same
`chromium-flags.conf` and the same extension — which the `omarchyWebapp` marker keeps from
looping.

### 3. Omarchy `.desktop` claims the scheme

`applications/Microsoft Teams Meeting.desktop` (NoDisplay), `Exec=omarchy-webapp-handler-teams %u`,
`MimeType=x-scheme-handler/msteams;`, `Icon=microsoft-teams`. `~/.local/share/applications`
precedes `/usr/share/applications` in the XDG search order, so once it is in place the
Omarchy handler beats `teams-for-linux`'s own registration, and the handler's deferral is
the one place that decides.

### 4. Firefox / Zen packaging

`default/firefox/policies-zen.json`: Omarchy's Firefox `Preferences` block, plus
`xpinstall.signatures.required=false` (required, see Constraints), `ExtensionSettings`
force-installing the committed XPI by its `gecko.id`, `DisableAppUpdate`, and
`DefaultSerialGuardSetting` (a real Zen policy in this build). `omarchy-install-browser`'s
Zen branch and the migration write it to `/etc/zen/policies/policies.json` (`install -d -m
755`, `install -m 644`).

## Decisions

1. **Content script, not `webNavigation`.** Phase 0 evidence: `webNavigation` is dead for
   `force_installed` extensions on Zen.
2. **Auto-fire, not a button.** The meeting id survives in the URL only briefly; a click
   loses the race.
3. **Loop guard matches the bare token `omarchyWebapp`.** Microsoft URL-encodes `=1` to
   `%3D1` in the launcher `url=` parameter; a literal `omarchyWebapp=1` check misses it and
   loops (seen live).
4. **Forward every `msteams:` URL to `teams-for-linux` when installed.** The strict check
   bought no security on that path and regressed non-meeting deep links.
5. **Set the signing pref via the Zen policy.** This build's effective default is true.
6. **Commit the XPI with a source-pin test.**

## Plan

Branch from `origin/quattro`. No dependency on PR 10367.

### Phase 0. Spike — DONE (2026-09-07)

Confirmed the hook and the fallback end to end (see Phase 0 results). No code from the spike
is kept; the spike extension lived in the session scratchpad.

### Phase 1. Handler, `.desktop`, and icon (tests first)

Files: `bin/omarchy-webapp-handler-teams`, `applications/Microsoft Teams Meeting.desktop`,
`applications/icons/microsoft-teams.png`, `test/shell.d/webapp-handler-teams-test.sh`.
Test with fake `omarchy-launch-webapp`/`setsid`/`uwsm-app` on `PATH` and a fake
`teams-for-linux` added or omitted (the handler resolves it through `omarchy-cmd-present`, a
`command -v` loop, so `PATH` is the whole mechanism). Cases: each A5 shape with and without
`teams-for-linux`, the marker joined with `&`/`?` and placed before any fragment, look-alike
host and non-meeting to the home page.

### Phase 2. Content-script extension, Chromium wiring, migration (tests first)

Files: `default/chromium/extensions/teams-join/{manifest.json,content.js}`,
`config/chromium-flags.conf`, `migrations/<epoch>.sh`,
`test/shell.d/chromium-teams-join-test.sh`, `test/shell.d/teams-join-migration-test.sh`.
Tests: manifest asserts MV3, `host_permissions` for the three hosts, a `content_scripts`
block at `document_start`, no `webNavigation`/`tabs`/background, non-empty `gecko.id`. A
`run_node_test` behaviour test evals `content.js` against a stubbed `window.location` and
`sessionStorage` and asserts: a meeting URL (each host, `:` and `%3a` forms, and the v2
fragment form) rewrites to the right `msteams:` target; a URL carrying `omarchyWebapp=1` and
its `omarchyWebapp%3D1` encoded form both stand down; a non-meeting URL and a repeat in the
same tab do not fire. Flags drift test; migration test modelled on the tmux one.

### Phase 3. Zen wiring and end-to-end check (tests first)

Files: `default/firefox/policies-zen.json`, `default/firefox/teams-join.xpi`,
`bin/omarchy-install-browser` (Zen branch), the Phase 2 migration (Zen step),
`test/shell.d/firefox-teams-join-test.sh`, `docs/file-layout.md`. Test (python3, zipfile +
json): `ExtensionSettings` key equals `gecko.id`; `install_url` names the committed XPI;
every key in `policies.json`'s `policies` is present and equal in `policies-zen.json`, plus
exactly the extra keys `xpinstall.signatures.required`, `ExtensionSettings`,
`DisableAppUpdate`, `DefaultSerialGuardSetting`; `policies.json` has no `ExtensionSettings`;
the XPI member names equal the source file names as a set and each member's bytes match.
Then hand-verify A1–A5 on this machine (`teams-for-linux` present, then removed), including
the no-`teams-for-linux` web-app fallback and the loop guard.

## Phase 0 results

Chromium and Zen, 2026-09-06/07. Full detail in the task memory; summary:

- The earlier `webNavigation` hook was **rejected**. It works when the extension is
  installed while the browser is running, but never delivers `onBeforeNavigate` to a
  `force_installed` (policy) extension on Zen — the ship path. `chrome.tabs.*` events on the
  same extension work; the internal `WebNavigation` module fires; only the extension-facing
  `webNavigation` API is silent, with a startup "listener not re-registered" error. An MV2
  persistent-background build force-installed at startup failed the same way, so the fault
  is the policy/startup install path, not the manifest version. Signing: this Zen build's
  effective `xpinstall.signatures.required` is true, so the policy must set it false (which
  the policy engine allows); verified the XPI then installs.
- The **content-script auto-fire hook** was **confirmed by John in both real browsers**: the
  script injects on the Teams hosts, auto-fires the moment the launcher page loads (before
  Microsoft's forward), and Teams for Linux opens on the meeting — no click, one-time allow.
  A button-on-click also works but loses the ~1–2 s race before Microsoft drops the meeting
  id. Meeting extraction pulls the meetup-join path from the launcher `url=` param, the
  query, or the fragment; stripping the fragment (an early bug) sent the app to chat.
- The **web-app fallback** (no `teams-for-linux`) was **validated end to end on the real
  system**: with `teams-for-linux` removed, our handler + `.desktop` routing `msteams:`, a
  real meeting click auto-fired, the handler opened a Chromium web-app window on the meeting,
  and the `omarchyWebapp` guard stood the window's copy of the extension down — no loop.
  The guard is load-bearing: a build matching the literal `omarchyWebapp=1` looped, because
  Microsoft URL-encodes it to `omarchyWebapp%3D1` in the launcher `url=` param; matching the
  bare token fixes it.
- Residual to confirm during implementation: whether the web-app window lands a signed-in
  session on the meeting join screen vs Teams home (a looping run drifted to `/v2/` home).

## Review log

This rebuilt doc reflects a changed design (content script, not `webNavigation`) and must
go through the review gate fresh. The lost prior doc had cleared claude-review (3 rounds),
grok-review (3 rounds, cap), and fable-review standing in for Sol (3 rounds, cap) on the
superseded `webNavigation` design; those clearances do not carry to this design.

| Gate | Stage | Round | Findings | Integrated |
|------|-------|-------|----------|------------|
| spec+plan | claude-review | 1 | | |
