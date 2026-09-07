# Teams meeting links open the Teams app on Omarchy

Tier: Full. Combined spec and plan. Rebuilt 2026-09-07 after the earlier scratchpad draft
(drafts 1–17) was lost with a cleaned session directory. This rebuild folds in the Phase 0
spike results, which changed the core hook from `webNavigation` to a content script. Revised 2026-09-07
after claude-review round 1 (16 findings integrated).

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
   click beyond the calendar link; at most a one-time browser "open msteams?" allow per Teams
   host (see Constraints).
2. "The Teams app" is `teams-for-linux` when installed, otherwise an Omarchy web-app window
   on the meeting. No configuration beyond installing `teams-for-linux`.
3. Supported browsers: Chromium-based browsers Omarchy manages through `*-flags.conf`, and
   Zen. Firefox proper is out of scope (see Constraints). Google Chrome 137+ ignores
   `--load-extension` in branded builds, a gap every Omarchy extension shares; Chrome is
   not a target.
4. Existing installs get everything through one migration. New installs get it through
   `/etc/skel` seeding plus `omarchy-finalize-user`: `omarchy-settings` ships
   `config/chromium-flags.conf` and `applications/*.desktop` into `/etc/skel/` (per
   `docs/file-layout.md`), so a new user starts with both files, and `omarchy-finalize-user`
   runs `omarchy-refresh-applications`, whose `update-desktop-database` builds the
   `~/.local/share/applications/mimeinfo.cache` that resolves `x-scheme-handler/msteams` to
   our `.desktop` (the same cache the migration rebuilds for existing users). This feature
   adds no finalize step of its own and no `install/user/chromium.sh` (that is for
   native-messaging extensions like `copy-url`). A browser installed after this ships needs
   nothing more: `omarchy-install-browser` copies the flags file and writes the Zen policy on
   every install, and the handler checks for `teams-for-linux` at run time. The one-shot
   migration is never the sole path, since `--first-install` stamps it done.
5. A non-meeting `msteams:` URL (chat, team, `/meet/<id>` deep links, which Teams web and
   Outlook emit) reaches `teams-for-linux` unchanged when the pacman/AUR package is
   installed (the one on `PATH`), so nothing that works with the native client today stops
   working. Without it, A5.2 applies. A Flatpak or AppImage Teams client that exports its
   own `x-scheme-handler/msteams` is out of scope (see Non-goals): our user-level `.desktop`
   outranks it and would send its links to the web fallback.
6. A machine with neither Teams app installed must still open the meeting, in a web-app
   window. The handler for that ships with Omarchy.

## Acceptance criteria

- A1. In Chromium with Omarchy flags, a meeting link opens the meeting in the Teams app.
  The link's browser tab does not join the meeting a second time. The script optionally calls
  `window.stop()` after firing to keep the tab off the web join screen; whether that leaves a
  usable launcher view or a blank tab, and whether it ever cancels the launch, is a Phase 3
  result, so the exact leftover-tab state is a residual, not a hard criterion. No click beyond
  the calendar link and the one-time "open msteams?" allow (Requirement 1).
- A2. Same in Zen.
- A3. With `teams-for-linux` absent and a signed-in Teams web session, the web-app window ends
  on the meeting join screen (the Phase 3 residual: landing on Teams home instead is fixed
  before the PR, not shipped). Without a session it ends on the Microsoft sign-in page. Only
  one window opens per meeting; Design 1's guards cover the drift cases, and a second window is
  possible only if the standalone guard fails to hold on some engine (an accepted residual).
- A4. With the `teams-for-linux` pacman/AUR package installed (on `PATH`), the meeting opens
  in it, with no `xdg-mime` setup.
- A5. Handler precedence, in order:
  1. A recognised meeting URL goes to `teams-for-linux` unchanged when installed, otherwise
     to a web-app window on the matching `https://` URL plus `omarchyWebapp=1` (joined with
     `&` when a query exists, `?` when not, placed before any fragment) -- unless the Design 2
     throttle refuses a repeat of the same meeting within its window, in which case the
     handler exits without a window.
  2. Any other `msteams:` URL goes to `teams-for-linux` unchanged when installed (its own
     allow-list decides). No argument, or a non-`msteams:` argument, opens `teams-for-linux`
     with no URL. Without `teams-for-linux`, everything in this item opens a web-app window
     on `https://teams.microsoft.com/`.
- A6. `./test/all` passes, with new tests for the handler, the extension (including the
  content-script behaviour and the loop guard), the XPI, and the migration.
- A7. Running the migration twice leaves one `teams-join` entry per flags file, one copy of
  the `.desktop` (followed by one `update-desktop-database` per run so the scheme resolves),
  and, on a box with Zen installed and no `/etc/zen/policies` yet, the Zen policy installed
  once: one `sudo` call on the first run (`install -D` does the dir and file together), none
  on the second. A box without Zen gets zero
  `sudo` calls and no prompt.
- A8. The content script injects on the three Teams hosts, finds the meeting (in the launcher
  `url=` parameter, the page query, or the URL fragment), and auto-navigates to
  `msteams://teams.microsoft.com/...` (the page host is dropped) at most once per meeting per
  tab. It does not fire in the web-app window or on a marked URL. Design 1 has the guard
  mechanics.

## Constraints

- No new packages. No native messaging. Shell plus a manifest-v3 content-script extension.
  No background script and no `webNavigation` (see Design 1 and Decisions).
- Chromium extensions ship unpacked through `--load-extension`, per existing convention.
- Zen's effective `xpinstall.signatures.required` default is **true** in the build tested
  (1.22b / Firefox 155 base): `gre` `greprefs.js` sets it false, but `browser/omni.ja`
  `defaults/preferences/firefox.js` overrides it to true, and the app default wins. So the
  unsigned `force_installed` XPI will not install unless the policy sets the pref false.
  Zen's policy engine allows that pref because `MOZ_REQUIRE_SIGNING` is false
  (`Policies.sys.mjs` pushes it into `allowedPrefixes`). `policies-zen.json` sets it with
  `"Status": "default"`, so a user can restore AMO checking (see Security).
  Firefox release refuses unsigned XPIs and would retry on every start, so it must not get
  this policy; supporting Firefox proper needs Mozilla signing and is out of scope.
- Zen sets `MOZ_SYSTEM_POLICIES` and `MOZ_APP_NAME=zen`, so it reads
  `/etc/zen/policies/policies.json` first and ignores the package-owned
  `/opt/zen-browser-bin/distribution/policies.json` when the `/etc` file exists. Omarchy
  owns the `/etc` file outright (`install -m 644`, no merge). The old
  `omarchy-install-browser` wrote `/opt/zen-browser/distribution`, a path nothing reads;
  this work writes the `/etc` path instead; the old `/opt/zen-browser/distribution` file (which
nothing reads -- Zen reads `/opt/zen-browser-bin/distribution`) is harmless and left in place.
- One extension source tree, used by both browser families. Firefox needs
  `browser_specific_settings.gecko.id`; Chromium ignores it. The extension is content-script
  only (no background), so the manifest-v3 vs event-page split that sank the earlier design
  does not arise. `host_permissions` for the three Teams hosts.
- Browsers prompt once before opening an external scheme. Because the script fires from
  Microsoft's own launcher page, the prompt's "always allow" is keyed to the
  `teams.microsoft.com` origin (a trusted origin). Chromium keys the grant per origin (Gecko's
  keying is not yet confirmed; Phase 3 records what Zen's prompt shows), so a
  user may see it once per Teams host they actually hit (up to three), not once globally;
  after granting on a host, later meetings on that host are silent.
  Not our problem to suppress.

## Non-goals

- Closing or redirecting the leftover browser tab after the handoff. The script may call
  `window.stop()` so the tab does not forward into the web join UI; Phase 3 decides whether to
  keep it (at `document_start` it can leave a blank tab and may race the launch). Either way
  the script never navigates the tab to another page or closes it.
- Personal-account `teams.live.com/meet/<id>` links (a different shape, no demand yet).
- Shipping Chromium support first and Zen later. Zen is the default browser here.
- Pinning `x-scheme-handler/msteams` in `default/applications/mimeapps.list`.
- A Flatpak or AppImage `teams-for-linux` (only the pacman/AUR package is detected). Its own
  `msteams` handler is outranked by the Omarchy `.desktop`; detecting it is possible but not
  worth it yet.
- Forwarding non-meeting `msteams:` deep links to a web-app window. The native client gets
  them when installed; without it they open the app home / Teams home, not a stray meeting.
- A `webNavigation`-based hook. Phase 0 proved it never reaches a `force_installed`
  extension on Zen. Rejected.

## Security

- The content script declares `host_permissions` for the three Teams hosts only (no
  `<all_urls>`, no `tabs`, no `webNavigation`, no background). It reads meeting URLs on
  those hosts and fires `msteams:` for the real meeting shape only.
- The `msteams:` launch is fired from a Teams-host page, so the browser's "always allow" is
  keyed to that origin (`teams.microsoft.com` in the normal flow), not an arbitrary page or
  the extension. The script is injected on the three Teams hosts and acts only on the
  meeting shape; it never runs on other origins.
- The `msteams:` value is bounded on each path. On the web-app path the handler re-validates
  host and path against its regex, so a look-alike host or stray path becomes the Teams home
  page, never a stray meeting window. On the native path the handler forwards every
  `msteams:` URL to `teams-for-linux` unchanged (Decision 4) -- bounded not by our regex but
  by the `msteams:` prefix (so no `--flag` is read as Electron argv) and by
  `teams-for-linux`'s own `msTeamsProtocols` allow-list. Either way the value is one quoted
  argv element no shell re-parses, and the handler regex rejects whitespace in its tail.
- The `omarchyWebapp` marker guard stops the web-app window's copy of the extension from
  re-firing `msteams:` and looping. It must match the bare token `omarchyWebapp` because
  Microsoft URL-encodes `=1` to `%3D1` inside the launcher `url=` parameter. Confirmed live:
  a build that matched the literal `omarchyWebapp=1` looped.
- `/etc/zen/policies/policies.json` force-installs the extension into every Zen profile.
  Its directory is created mode 755, root-owned, never through the installer's
  `chmod a+rw` helper.
- `xpinstall.signatures.required=false` in the Zen policy turns off AMO signature checking
  for every extension in Zen, not only ours -- the real cost of shipping an unsigned XPI.
  The policy sets it `"Status": "default"`, so a user can restore it (accepting that our
  extension is then disabled at next startup, not merely un-updated). The way out if this
  trade-off is rejected is to
  self-distribution-sign the XPI through AMO. Flagged in Decisions for John.

## Design

Data flow: click a meeting link in the browser, the content script on Microsoft's launcher
page rewrites the navigation to `msteams://...`, the browser hands it to the desktop
(Chromium 151 asks the `xdg-desktop-portal` `OpenURI` when the portal runs, `xdg-open`
otherwise; both resolve `x-scheme-handler/msteams` through the desktop database), the
Omarchy `.desktop` owning `msteams` runs the handler, and the handler picks `teams-for-linux`
or a web-app window.

### 1. Content script: `default/chromium/extensions/teams-join`

Manifest v3, content-script only, no background, no UI. The `content_scripts` block matches
exactly `https://teams.microsoft.com/*`, `https://teams.cloud.microsoft/*`, and
`https://teams.live.com/*` (no `http://`, no `<all_urls>`) at `run_at: document_start`, with
`host_permissions` for the same three hosts. The script:

- Finds the meeting path `/l/meetup-join/19(:|%3a)...` in the launcher `url=` parameter, the
  page query, or the URL fragment (the Linux web client is
  `teams.microsoft.com/v2/?meetingjoin=true#/l/meetup-join/...`), keeps the meeting's own
  `context=` query, drops only the launcher's added params (`anon`, `deeplinkId`,
  `launchAgent`, `enablemcas`, `suppressPrompt`) wherever they sit, and rebuilds
  `msteams://teams.microsoft.com/l/meetup-join/...`. It assumes the `url=` parameter is
  URL-encoded (so `context`'s own `{`/`"` arrive percent-encoded); `searchParams.get`
  decodes one layer, and the extractor stops only at a fragment or whitespace.
- Standalone guard (the origin-independent one): the web-app window is a Chromium `--app`
  window, which reports `display-mode: standalone`; the script stands down there, so it never
  fires in a web-app window regardless of origin, marker, or elapsed time. This closes the
  drift the two guards below cannot: a no-session sign-in that returns on a different Teams
  host after more than 20s (past the throttle, past the per-origin latch). Phase 3 confirms
  standalone distinguishes the web-app window from a normal tab; the marker and latch below
  are the proven fallback where it does not.
- Marker loop guard: if the page URL contains the `omarchyWebapp` token (any form, including
  `omarchyWebapp%3D1`), it stands down. Firing and standing down both latch a per-meeting key
  in `sessionStorage` (per origin per tab), so a later same-origin hop for that meeting -- a
  launcher->`/v2/` hop that drops the marker (the observed drift) -- does not re-fire, while a
  different meeting in the same tab still can. A cross-origin drift escapes `sessionStorage`;
  the handler's ~20s throttle is the origin-independent backstop.
- Otherwise it auto-navigates the top frame to the `msteams:` form and latches, so it fires
  at most once per meeting per tab. A manual reload of the launcher page after dismissing the
  prompt does not re-fire for that meeting in that tab (a fresh tab, or a different meeting,
  does).

Core of `content.js` (the marker guard was validated in the Phase 0 spike; the standalone
stand-down and `window.stop()` are Phase 3 checks -- `window.stop()` at `document_start` can
leave a blank tab and may race the launch):

```js
// Match the meetup-join path (id required, so `+`). `[^#\s]+` keeps encoded chars and
// stops only at a fragment or whitespace, which browsers never leave raw in a URL.
function meetingPath(str) {
  if (!str) return null;
  var m = str.match(/\/l\/meetup-join\/19(?::|%3[aA])[^#\s]+/);
  if (!m) return null;
  var raw = m[0], q = raw.indexOf("?");
  if (q < 0) return raw;
  // Keep the meeting's own query (context=...); drop only the launcher's added params,
  // wherever they sit, so a leading deeplinkId= cannot slice off context=.
  var drop = /^(anon|deeplinkId|launchAgent|enablemcas|suppressPrompt)$/;
  var kept = raw.slice(q + 1).split("&").filter(function (x) { return !drop.test(x.split("=")[0]); });
  return kept.length ? raw.slice(0, q) + "?" + kept.join("&") : raw.slice(0, q);
}
var href = window.location.href;
var marker = href.indexOf("omarchyWebapp") !== -1;      // loop guard: bare token, survives URL-encoding
// Origin- and time-independent guard: the web-app window the handler opens is a Chromium
// --app window, which reports standalone; a normal browser tab does not. Standing down here
// closes the cross-origin / >20s sign-in drift the per-origin latch and the 20s throttle can
// miss. Phase 3 confirms it distinguishes the two; marker + throttle stay as the proven
// fallback for any engine where it does not.
var standalone = false;
try { standalone = window.matchMedia("(display-mode: standalone)").matches; } catch (e) {}
var path = null;
try { var u = new URL(href); path = meetingPath(u.searchParams.get("url")) || meetingPath(href); }
catch (e) { path = meetingPath(href); }
var target = path ? ("msteams://teams.microsoft.com" + path) : null;
// Per-meeting latch (per origin per tab): key on the normalized meeting path so the same
// meeting via different encodings maps to one key. Firing OR standing down latches it, so a
// later same-origin hop for THIS meeting -- e.g. a launcher->/v2/ hop that drops the marker
// -- does not fire again, while a different meeting in the same tab still can (A3, A8).
var key = path ? ("teamsjoin:" + path.replace(/%3[aA]/g, ":").replace(/%40/g, "@").split("?")[0]) : null;
var done = false;
try { if (key) done = !!sessionStorage.getItem(key); } catch (e) {}
if (!done && key) {
  try { sessionStorage.setItem(key, "1"); } catch (e) {}
  if (!marker && !standalone) {
    window.location.href = target;
    try { window.stop(); } catch (e) {}  // halt the launcher's forward so the tab does not become the web join UI (A1)
  }
}
```

**Why a content script and not `webNavigation`.** Phase 0 proved `webNavigation` events
never reach a `force_installed` (policy-installed) extension on Zen: the extension runs and
gets `chrome.tabs.*` events, but its primed `webNavigation` listener fails to reconnect at
startup ("listener not re-registered"), so `onBeforeNavigate` never fires. Temporary and
post-startup installs work; the ship path (policy) does not. A content script uses a
different injection path that does not depend on that primed-listener step. It was confirmed
live on Zen only as a temporary add-on against the real Teams hosts; injection from the real
`force_installed` `/etc/zen` policy is the one thing Phase 0 did not test and is Phase 3's
first hand-check. If MV3 host permissions are not granted under policy, the fallback is an
MV2 XPI for Zen (which breaks the one-source-tree design and the pin test) -- that decision is
on record before Phase 1. The meetup-join URL 302s to the launcher and never commits as a page, so
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
if [[ $url =~ ^msteams:/*teams\.(microsoft\.com|live\.com|cloud\.microsoft)/(l/meetup-join/19(:|%3[aA])[^[:space:]]+)$ ]]; then  # any leading slashes: msteams:teams. .. msteams:///teams.
  host="teams.${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"
elif [[ $url =~ ^msteams:/*(l/meetup-join/19(:|%3[aA])[^[:space:]]+)$ ]]; then  # any leading slashes, host-less: msteams:l/.. msteams:///l/..
  host="teams.microsoft.com"; path="${BASH_REMATCH[1]}"
fi
# --gtk-version=3 mirrors the flag in teams-for-linux's own packaged .desktop Exec.
if omarchy-cmd-present teams-for-linux; then
  if [[ $url == msteams:* ]]; then exec setsid uwsm-app -- teams-for-linux --gtk-version=3 "$url"
  else exec setsid uwsm-app -- teams-for-linux --gtk-version=3; fi
fi
if [[ -n $path ]]; then
  # Origin-independent loop backstop: refuse a second web-app window for the same meeting
  # within ~20s. The content-script latch is per origin; a cross-origin launcher hop that
  # drops the marker (teams.microsoft.com -> teams.cloud.microsoft) would otherwise re-enter.
  # Normalize the id the way the content script normalizes its key, so the same meeting in
  # different encodings (launcher-decoded %3a/%40 vs raw :/@) maps to one id.
  id="${path%%\?*}"; id="${id%%#*}"; id="${id//%3a/:}"; id="${id//%3A/:}"; id="${id//%40/@}"
  state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
  stamp="$state/teams-join-last"; now=$(printf '%(%s)T' -1)
  if [[ -f $stamp ]]; then read -r last_id last_t < "$stamp" || true
    [[ $last_id == "$id" ]] && (( now >= last_t && now - last_t < 20 )) && exit 0  # now>=last_t: a future stamp (clock stepped back) must not swallow
  fi
  mkdir -p "$state"; printf '%s %s\n' "$id" "$now" > "$stamp.$$" && mv -f "$stamp.$$" "$stamp"  # atomic; rare simultaneous same-meeting click can still open two
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
`chromium-flags.conf` and the same extension -- which the `omarchyWebapp` marker (same
origin) plus the ~20s throttle (any origin) keep from looping. The web-app URL keeps the
matched host (`teams.live.com` / `teams.cloud.microsoft` stay themselves), even though the
content script always rebuilds `msteams:` to `teams.microsoft.com`; `teams-for-linux`'s
allow-list accepts all three and `context` carries the tenant, so both are fine. The
handler's three-host regex therefore guards external `msteams:` input, not anything the
script emits. The throttle sits after the native-client branch, so on the native path a
cross-origin drift would at worst hand `teams-for-linux` the same meeting twice (a duplicate
join prompt, not a loop); accepted. Twenty seconds covers a cold Chromium start plus the
redirect chain; a re-click of the same meeting inside that window is swallowed on purpose.

### 3. Omarchy `.desktop` claims the scheme

`applications/Microsoft Teams Meeting.desktop` (NoDisplay), `Exec=omarchy-webapp-handler-teams %u`,
`MimeType=x-scheme-handler/msteams;`, `Icon=microsoft-teams`. `~/.local/share/applications`
precedes `/usr/share/applications` in the XDG search order, so once it is in place the
Omarchy handler beats `teams-for-linux`'s own registration, and the handler's deferral is
the one place that decides.

### 4. Firefox / Zen packaging

`default/firefox/policies-zen.json`: Omarchy's Firefox `Preferences` block (the Wayland and
media tweaks -- `apz.overscroll.enabled`, `media.ffmpeg.vaapi.enabled`,
`media.hardware-video-decoding.force-enabled`, `widget.disable-swipe-tracker`,
`widget.wayland.fractional-scale.enabled` -- which have NEVER been live on Zen, since the old
installer wrote a path Zen ignores; moving to `/etc/zen` newly applies them to Zen, which
Phase 3 confirms is benign -- expect `apz.overscroll.enabled` under about:policies > Errors,
not in Zen's allowed-prefix list; pre-existing in `policies.json`, so not a regression), plus
`xpinstall.signatures.required=false` (`Status: default`, required; see Constraints and
Security), `ExtensionSettings`
force-installing the XPI by its `gecko.id` with `install_url` the fixed system path
`file:///usr/share/omarchy/default/firefox/teams-join.xpi` (where `default/**` installs; the
Phase 0 spike used the worktree path), and the two keys `zen-browser-bin`
already ships in its own `distribution/policies.json` -- `DisableAppUpdate` (Zen is updated
by pacman/AUR, not by itself) and `DefaultSerialGuardSetting` (its Web Serial default).
Those two are carried forward because the `/etc` file shadows the distribution file that set
them; confirm they still match `zen-browser-bin`'s shipped values at implementation and drop
either if the vendor stops shipping it. `omarchy-install-browser`'s Zen branch and the
migration write the file to `/etc/zen/policies/policies.json` with a single
`install -D -m 644` (one privileged call: it creates the mode-755 directory and the mode-644
file together).

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
7. **Signing pref `Status: default`, not `locked`.** Disabling AMO checking is a real cost, so
   let the user restore it; if that trade-off is rejected, AMO self-distribution signing is
   the alternative. Open for John.
8. **Zen policy delivery -- OPEN FOR JOHN.** (a) the migration + installer write
   `/etc/zen/policies/policies.json` with `sudo install -D` (the current plan), or (b) ship a
   package-owned `etc/zen/policies/policies.json` drop-in, as the repo already ships
   `etc/docker/` and `etc/modprobe.d/`. Option (b) removes the migration's Zen step, the
   installer write, the `omarchy-remove-browser` cleanup, the fake-`sudo` test, A7's sudo
   accounting, and the non-wheel-user failure mode: pacman drops the file on `omarchy-settings`
   upgrade, Zen reads it next start, nothing else touches `/etc/zen`. Cost: a 1KB inert file on
   non-Zen boxes, the out-of-repo PKGBUILD dependency the icon and XPI already have, and
   pre-cleaning the Phase 0 `/etc/zen` residue before the upgrade (pacman will not overwrite an
   unowned file). Recommended: (b). If taken, Phase 3 shrinks to the XPI, the policy file, the
   pin test, and the hand-checks, and the migration/installer Zen findings drop.

## Plan

Branch from `origin/quattro`. No dependency on PR 10367.

### Phase 0. Spike — DONE (2026-09-07)

Confirmed the hook and the fallback end to end (see Phase 0 results). No code from the spike
is kept; the spike extension lived in the session scratchpad.

### Phase 1. Handler, `.desktop`, and icon (tests first)

Step 0, before any test code, settle the two residuals that can fork the design. On a fresh
Zen profile with the real `force_installed` `/etc/zen` policy and a zipped Phase 0 content
script, confirm the script injects on the launcher page (temporary add-ons auto-grant host
permissions, so Phase 0 is no evidence for the policy path). If it injects, proceed MV3; if
not, decide the MV2-for-Zen fork now. In the same spike, confirm `window.stop()` after the
`msteams:` assign does not cancel the launch on either engine; keep it only if the launch
fires every time (a blank leftover tab is acceptable), else drop it from Design 1 and the
tests.

Files: `bin/omarchy-webapp-handler-teams`, `applications/Microsoft Teams Meeting.desktop`,
`applications/icons/Microsoft Teams.png` (source icons are Title-Case like
`Google Messages.png`; `omarchy-settings` installs them lowercase-dashed into hicolor, so
`Icon=microsoft-teams` resolves -- confirm the installed name against the `omarchy-settings`
PKGBUILD, which is not in this repo), `test/shell.d/webapp-handler-teams-test.sh`.
Test with fake `omarchy-launch-webapp`/`setsid`/`uwsm-app` on `PATH`, a fake `teams-for-linux`
added or omitted (the handler resolves it through `omarchy-cmd-present`, a `command -v` loop,
so `PATH` is the whole mechanism), and `XDG_STATE_HOME` pointed at a fresh temp dir per case
so the throttle and the real `~/.local/state` are never touched. Cases: each A5 shape with and
without `teams-for-linux`, the marker joined with `&`/`?` and placed before any fragment,
look-alike host and non-meeting to the home page; and the throttle -- the same meeting id
twice inside the window opens once (the second call exits 0 with no `omarchy-launch-webapp`),
the same id after the window opens again, a different id always opens, two encodings of one id
(`%3a`/`%40` vs `:`/`@`) count as the same, and an empty or one-field stamp opens. The
`.desktop` is asserted too: `MimeType=x-scheme-handler/msteams;`, `Exec=omarchy-webapp-handler-teams %u`,
`NoDisplay=true`, and `Icon=` equal to the lowercase-dashed name of a PNG in
`applications/icons/` (no existing test reads `applications/*.desktop` content, so a typo
ships silently otherwise).

### Phase 2. Content-script extension, Chromium wiring, migration (tests first)

Files: `default/chromium/extensions/teams-join/{manifest.json,content.js}`,
`config/chromium-flags.conf`, `migrations/<epoch>.sh`,
`test/shell.d/chromium-teams-join-test.sh`, `test/shell.d/teams-join-migration-test.sh`.
The migration, each step idempotent: (1) copy the `.desktop` into
`~/.local/share/applications/` if absent or different, then run
`update-desktop-database ~/.local/share/applications` unconditionally (cheap and idempotent) so `mimeinfo.cache` learns the handler
(copying the file alone leaves the scheme unresolved) -- a narrow copy, not
`omarchy-refresh-applications`, which re-copies every shipped `.desktop` (overwriting user
edits) and runs `install/user/mise.sh`; (2) add `extensions/teams-join` to
`--load-extension=` in each flags file, iterating the browser list from the whatsapp-slim
migration plus `brave-origin` (the installer writes `brave-origin-flags.conf`, which that
loop's `brave-origin-beta` misses); the migration then echoes "restart Chromium/Brave to load
the Teams extension", since the flags edit only applies on the next browser start. The Zen
policy step is Phase 3 (it needs Phase 3's
`policies-zen.json` and XPI), so Phase 2 is self-contained without them.
Tests: manifest asserts MV3, `content_scripts.matches` equals exactly the three `https://`
host patterns (no `http://`, no `<all_urls>`), `host_permissions` for the same three,
`run_at: document_start`, no `webNavigation`/`tabs`/background, non-empty `gecko.id`. A
`run_node_test` behaviour test runs `content.js` with `vm.runInNewContext` (a fresh sandbox
per case, since Node 26 ships a native `sessionStorage` global and a direct `eval` lets the
script's `var`s clobber the harness), stubbing `window.location`, `sessionStorage`,
`matchMedia`, and `window.stop`, and asserts: a meeting URL (each host, `:` and `%3a` forms, the v2 fragment
form, a single-encoded `context=` in the `url=` param, and a `deeplinkId=` before
`context=`) rewrites to `msteams://teams.microsoft.com` + path for all three page hosts (the
page host is always dropped) with `context` kept; a URL carrying `omarchyWebapp=1` and its
`omarchyWebapp%3D1` encoded form both stand down and latch the tab (a following marker-less
`/v2/` hop in the same tab does not fire); a `matchMedia('(display-mode: standalone)')` stub
returning `matches: true` yields no fire; a non-meeting URL and any repeat in the same tab do
not fire; and a stubbed `window.stop` is called after a fire and not on a stand-down. Flags
drift test; migration test modelled on the tmux one: run twice, asserting one flags entry and
one `.desktop` per run, one `update-desktop-database` call per run, and the `brave-origin`
entry. It stubs `omarchy-pkg-present` (Zen absent) and `update-desktop-database` on `PATH` so
`./test/all` never runs a real `sudo`/system write on a dev box that has Zen; the Zen-present
cases live in `firefox-teams-join-test.sh`.

### Phase 3. Zen wiring and end-to-end check (tests first)

Files: `default/firefox/policies-zen.json`, `default/firefox/teams-join.xpi`,
`bin/omarchy-install-browser` (Zen branch), the Zen policy step ADDED to the Phase 2
migration here (gated on `omarchy-pkg-present zen-browser-bin`, the `cmp -s` run unsudoed and
skipping when `/etc/zen/policies/policies.json` already matches, `install -D` so a non-Zen box
and a matching second run make no `sudo` call; on an `install -D` failure -- a denied or
timed-out `sudo` -- the step prints a message pointing the user at `omarchy install browser
zen` and STILL exits 0, per the `migrations/*.sh` convention that a non-zero migration aborts
every migration queued behind it (a non-wheel user must not be blocked; that user re-runs the
installer to get the policy)), `bin/omarchy-remove-browser` (Zen branch: add
`sudo rm -rf /etc/zen` (the whole dir, matching the Brave branch's `/etc/brave`) --
`omarchy-remove-browser` calls `sudo` directly, not
`as_root`, and the two Brave branches already `rm -rf` their policy dir), `test/shell.d/firefox-teams-join-test.sh` (also, with a fake `sudo`,
reading the Zen policy path from an env override (default `/etc/zen/policies/policies.json`,
as `migrations/1785273276.sh` overrides its target) pointed at a temp dir, with `omarchy-pkg-present`
stubbed on `PATH` and a fake `sudo` that logs then `exec`s (so the file is really written and
the matching-second-run case is observable), asserting the `install -D`/`sudo` counts across
two runs for Zen-present-empty = one, Zen-present-matching = zero, and Zen-absent = zero;
and running `bin/omarchy-install-browser`'s zen branch with its helpers stubbed (as
`desktop-entry-launch-test.sh` does) and a logging fake `sudo`, asserting the exact
`install -D -m 644 .../policies-zen.json /etc/zen/policies/policies.json` call and no
`chmod a+rw`),
`docs/file-layout.md` (a `default/firefox/*` row for the installer-written
`/etc/zen/policies/policies.json`). Test (python3, zipfile + json): `ExtensionSettings` key
equals `gecko.id` and its `installation_mode` is exactly `force_installed` (not
`normal_installed`, missing, or hyphenated, any of which would silently not force-install); `install_url` equals
`file:///usr/share/omarchy/default/firefox/teams-join.xpi` exactly (not merely contains
`teams-join.xpi`); `policies-zen.json`'s `Preferences` is a superset of `policies.json`'s
`Preferences`, adding exactly `xpinstall.signatures.required` = `{Value: false, Status:
default}` (a Firefox preference, set inside `Preferences`, not a top-level policy key); the
only top-level `policies` keys beyond `Preferences` are `ExtensionSettings`,
`DisableAppUpdate`, and `DefaultSerialGuardSetting`; `policies.json` has no `ExtensionSettings`; the XPI member names
equal the source file names as a set and each member's bytes match; and, so an edit
cannot ship without the version bump Zen needs to reinstall, the test compares
`manifest.version` against the base manifest at `${TEST_GIT_UPSTREAM:-origin/quattro}`
(`git show <base>:default/chromium/extensions/teams-join/manifest.json`, borrowing the
variable name from `test/shell.d/update-available-test.sh`, `none` to skip) whenever the tracked
`content.js`/`manifest.json` differ from that base, and fails with a "bump the version"
message when they differ but the version does not. A missing base (this branch before merge,
or a checkout without the ref) is a new extension: pass, running only the XPI byte-match. The
test `require_command git` since it is otherwise python-only. A bare sha256 pin would not
enforce the bump: re-pinning the new sha under the same version passes. Then hand-verify A1–A5 on this machine.
Pre-clean first, so Phase 0 residue does not mask the shipped mechanism: remove any
`x-scheme-handler/msteams` pin from `~/.config/mimeapps.list` and any leftover `/etc/zen`,
confirm `xdg-mime query default x-scheme-handler/msteams` is empty, then run the migration and
confirm the scheme resolves through `mimeinfo.cache` alone (this also makes the "no
`/etc/zen/policies` yet, one sudo" A7 case real). FIRST hand-check: confirm the content script
injects on the launcher page from the real `force_installed` `/etc/zen` policy on a fresh Zen
profile (Phase 0 tested only a temporary add-on). Then, with `teams-for-linux` present then
removed, the no-`teams-for-linux` web-app fallback and the loop guard (A3 -- watch for a
second window on the same-origin `/v2/` drift and on a cross-origin
`teams.microsoft.com`->`teams.cloud.microsoft` hop, which only the handler throttle catches);
a meeting link opened from outside the browser (`xdg-open`, a mail client, a terminal), where
the page carries no user gesture -- if Chromium's external-protocol gate blocks it there,
that is an accepted limitation of the click-driven design, not a ship blocker (record the
result); and the Zen-default case with no Chromium running, so a fresh Chromium process must
read the flags and load the extension. Confirm the residual: a signed-in web session lands on
the meeting join screen, not Teams home. Confirm the force-install works with `Status:
default` on a fresh Zen profile (a profile with a user-set `xpinstall.signatures.required=true`
in `prefs.js` would still block it). Confirm the standalone guard: `matchMedia('(display-mode:
standalone)').matches` is true in the Chromium `--app` web-app window and false in a normal
tab (in both browsers); this is what keeps the web-app window from firing on any hop. If it
does not hold on an engine, the marker + throttle remain the guard there. It is defense
ALONGSIDE the marker, never a replacement -- dropping `omarchyWebapp` would contradict A5.1,
A8, and Decision 3. Also check the leftover calendar tab after a click: its URL and UI stay
on the launcher page, not the web join screen (A1). Rollback, if the feature is later pulled: a migration removes
the flags entry, the `.desktop`, and `/etc/zen/policies`.

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
- The **content-script auto-fire hook** was **confirmed by John in both real browsers**
  (Chromium via `--load-extension`, the ship path; Zen via a **temporary add-on**, NOT the
  `force_installed` policy ship path -- that injection is a Phase 3 residual): the
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
| spec+plan | claude-review | 1 (full) | 16 (0 blocker, 12 should-fix, 4 nit) | 16 |
| spec+plan | claude-review | 2 (full, heavy round 1) | 10 (0 blocker, 5 should-fix, 5 nit) | 10 |
| spec+plan | claude-review | 3 (delta) | 10 (0 blocker, 4 should-fix, 6 nit) | 10; cap reached, clean |
| spec+plan | grok-review | 1 | 7 (1 P1, 3 P2, 3 P3) | 7 |
| spec+plan | grok-review | 2 | 6 (0 P1, 4 P2, 2 P3) | 6 |
| spec+plan | grok-review | 3 | 9 (0 P1, 6 P2, 3 P3) | 9; cap reached |
| spec+plan | fable-review (for Sol) | 1 | 11 (1 blocker, 5 should-fix, 5 nit) | 10; nit "de-dup loop-guard rationale" surfaced to John |
| spec+plan | fable-review (for Sol) | 2 | 11 (0 blocker, 6 should-fix, 5 nit) | 11; Decision 8 (package-owned /etc) open for John |
