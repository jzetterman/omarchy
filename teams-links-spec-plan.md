# Teams meeting links open the Teams app on Omarchy

Tier: Full. Combined spec and plan. Rebuilt 2026-09-07 after the earlier scratchpad draft
(drafts 1–17) was lost with a cleaned session directory. This rebuild folds in the Phase 0
spike results, which changed the core hook from `webNavigation` to a content script.
Revision history: see the Review log.

## Problem

On Windows and macOS, clicking a Teams meeting link in a calendar hands the meeting to the
Teams app. On Omarchy the link opens in a browser tab and stays there.

Zoom already works the app way on Omarchy. Its join page fires `zoommtg://`, Omarchy claims
that scheme with `applications/Zoom.desktop`, and `bin/omarchy-webapp-handler-zoom` reopens
the meeting in a Chromium app window.

Teams cannot copy that pattern as-is. Verified with Playwright, 2026-09-06:

- Microsoft's join page decides in page JavaScript, from the browser's user agent, whether
  to fire `msteams:`. It fires for Windows and macOS agents only.
- With any Linux agent it never fires the scheme. It goes to the web client at
  `teams.microsoft.com/light-meetings/launch`.
- The decision is client-side. Spoofing the HTTP header alone does not change it.

So on Linux the browser itself has to turn the join link into an `msteams:` URL. Once the
scheme fires, the rest is the Zoom pattern. The rewrite is a small browser extension.

The pending upstream PR basecamp/omarchy#10367 (Install > Service > Microsoft) installs a
plain Teams web app. This work does not depend on it and does not change it.

## Requirements

1. Clicking a Teams meeting link (either shape in Requirement 7, on any host in
   Requirement 8) in a supported browser opens the meeting in the Teams app instead of a
   browser tab. No extra click beyond the calendar link. At most a one-time browser "open
   msteams?" allow per Teams host (see Constraints).
2. "The Teams app" is `teams-for-linux` when installed, otherwise an Omarchy web-app window
   on the meeting. On the commercial and consumer clouds, no configuration beyond installing
   `teams-for-linux`. A GCC High or DoD user must also point `teams-for-linux` at their cloud
   in its own config (A9, Decision 9). The web-app fallback needs no configuration on any
   cloud.
3. Supported browsers: Chromium-based browsers Omarchy manages through `*-flags.conf`, and
   Zen. Firefox proper is out of scope (see Constraints). Google Chrome 137+ ignores
   `--load-extension` in branded builds, a gap every Omarchy extension shares. Chrome is
   not a target.
4. Existing installs get everything through one migration. New installs get it through
   `/etc/skel` seeding plus `omarchy-finalize-user`. `omarchy-settings` ships
   `config/chromium-flags.conf` and `applications/*.desktop` into `/etc/skel/` (per
   `docs/file-layout.md`), so a new user starts with both files. `omarchy-finalize-user` runs
   `omarchy-refresh-applications`, whose `update-desktop-database` builds
   `~/.local/share/applications/mimeinfo.cache`. That cache resolves
   `x-scheme-handler/msteams` to our `.desktop`; the migration rebuilds the same cache for
   existing users. This feature adds no finalize step of its own and no
   `install/user/chromium.sh` (that is for native-messaging extensions like `copy-url`). A
   browser installed after this ships needs nothing more: `omarchy-install-browser` copies the
   flags file, the Zen policy is already on disk as a package-owned file (Decision 8b), and
   the handler checks for `teams-for-linux` at run time. The one-shot migration is never the
   sole path, since
   `--first-install` stamps it done.
5. A non-meeting `msteams:` URL (chat, team, and other non-join deep links, which Teams web
   and Outlook emit) reaches `teams-for-linux` unchanged when the pacman/AUR package is
   installed (the one on `PATH`). Nothing that works with the native client today stops
   working. Without it, A5.2 applies. A Flatpak or AppImage Teams client that exports its
   own `x-scheme-handler/msteams` is out of scope (see Non-goals): our user-level `.desktop`
   outranks it and would send its links to the web fallback.
6. A machine with neither Teams app installed must still open the meeting, in a web-app
   window. The handler for that ships with Omarchy.

## Acceptance criteria

- A1. In Chromium with Omarchy flags, a meeting link opens the meeting in the Teams app.
  The link's browser tab does not join the meeting a second time. The script may call
  `window.stop()` after firing to keep the tab off the web join screen; Phase 1 Step 0
  decides whether it stays, and Phase 3 records the leftover-tab state. So the exact
  leftover-tab state is a residual, not a hard criterion. No click beyond the calendar link
  and the one-time "open msteams?" allow (Requirement 1).
- A2. Same in Zen.
- A3. With `teams-for-linux` absent and a signed-in Teams web session, the web-app window ends
  on the meeting join screen. Landing on Teams home instead is the Phase 3 residual: fixed
  before the PR, not shipped. Without a session it ends on the Microsoft sign-in page. Only
  one window opens per meeting. Design 1's guards cover the drift cases. A second window is
  possible only if the standalone guard fails to hold on some engine, an accepted residual.
- A4. With the `teams-for-linux` pacman/AUR package installed (on `PATH`), the meeting opens
  in it, with no `xdg-mime` setup.
- A5. Handler precedence, in order:
  1. A recognised meeting URL (either shape in Requirement 7 with a listed host in
     Requirement 8, or the host-less v1 form `msteams:/<path>` that Design 2 already
     accepts) goes to `teams-for-linux` unchanged when installed. Otherwise it goes to a
     web-app window on the matching `https://` URL plus `omarchyWebapp=1` (joined with `&`
     when a query exists, `?` when not, placed before any fragment). Host-less v1 falls
     back to `teams.microsoft.com`. The Design 2 throttle is the exception: a repeat of
     the same meeting inside its window makes the handler exit without a window.
  2. Any other `msteams:` URL goes to `teams-for-linux` unchanged when installed (its own
     allow-list decides). No argument, or a non-`msteams:` argument, opens `teams-for-linux`
     with no URL. Without `teams-for-linux`, everything in this item opens a web-app window
     on `https://teams.microsoft.com/`.
- A6. `./test/all` passes, with new tests for the handler, the extension (including the
  content-script behaviour and the loop guard), the XPI, and the migration.
- A7. Running the migration twice leaves one `teams-join` entry per flags file and one copy
  of the `.desktop` (followed by one `update-desktop-database` per run so the scheme
  resolves). The migration makes no `sudo` call and shows no prompt, with or without Zen: the
  Zen policy ships as a package-owned file (Decision 8b), not through the migration.
- A8. The content script injects on the Requirement 8 host set, finds the meeting (classic
  `/l/meetup-join/` or short `/meet/`, in the launcher `url=` parameter, the page query, or
  a `/v2/` URL fragment), and auto-navigates to `msteams://<page-host>/...` (the page host
  is kept) at most once per meeting per tab. It does not fire in the web-app window or on a
  marked URL. Design 1 has the guard mechanics.

## Constraints

- No new packages. No native messaging. Shell plus a manifest-v3 content-script extension.
  No background script and no `webNavigation` (see Design 1 and Decisions).
- Chromium extensions ship unpacked through `--load-extension`, per existing convention.
- Zen's effective `xpinstall.signatures.required` default is true in the build tested
  (1.22b / Firefox 155 base). `gre` `greprefs.js` sets it false, but `browser/omni.ja`
  `defaults/preferences/firefox.js` overrides it to true, and the app default wins. So the
  unsigned `force_installed` XPI will not install unless the policy sets the pref false.
  Zen's policy engine allows that pref because `MOZ_REQUIRE_SIGNING` is false
  (`Policies.sys.mjs` pushes it into `allowedPrefixes`). The Zen policy sets it with
  `"Status": "default"`, so a user can restore AMO checking (see Security).
  Firefox release refuses unsigned XPIs and would retry on every start, so it must not get
  this policy. Supporting Firefox proper needs Mozilla signing and is out of scope.
- Zen sets `MOZ_SYSTEM_POLICIES` and `MOZ_APP_NAME=zen`. It reads
  `/etc/zen/policies/policies.json` first and ignores the package-owned
  `/opt/zen-browser-bin/distribution/policies.json` when the `/etc` file exists. Omarchy
  ships the `/etc` file package-owned via `omarchy-settings` (Decision 8b), so nothing writes
  it at runtime. The old `omarchy-install-browser` wrote `/opt/zen-browser/distribution`, a
  path nothing reads (Zen reads `/opt/zen-browser-bin/distribution`). That old file is
  harmless and stays in place.
- One extension source tree, used by both browser families. Firefox needs
  `browser_specific_settings.gecko.id`; Chromium ignores it. The extension is content-script
  only (no background), so the manifest-v3 vs event-page split that sank the earlier design
  does not arise. `host_permissions` for the Requirement 8 host set.
- Browsers prompt once before opening an external scheme. Because the script fires from
  Microsoft's own launcher page, the prompt's "always allow" is keyed to the
  `teams.microsoft.com` origin (a trusted origin). Chromium keys the grant per origin.
  Gecko's keying is not yet confirmed; Phase 3 records what Zen's prompt shows. So a user
  may see the prompt once per Teams host they hit (up to the size of the host set), not once globally. After
  granting on a host, later meetings on that host are silent. Not our problem to suppress.

## Non-goals

- Closing or redirecting the leftover browser tab after the handoff. The script may call
  `window.stop()` so the tab does not forward into the web join UI; Phase 1 Step 0 decides
  whether to keep it. Either way the script never navigates the tab to another page or
  closes it.
- Shipping Chromium support first and Zen later. Zen is the default browser here.
- Pinning `x-scheme-handler/msteams` in `default/applications/mimeapps.list`.
- A Flatpak or AppImage `teams-for-linux` (only the pacman/AUR package is detected). Its own
  `msteams` handler is outranked by the Omarchy `.desktop`. Detecting it is possible but not
  worth it yet.
- Forwarding non-meeting `msteams:` deep links to a web-app window. The native client gets
  them when installed. Without it they open the app home / Teams home, not a stray meeting.
- A `webNavigation`-based hook. Phase 0 proved it never reaches a `force_installed`
  extension on Zen. Rejected (Decision 1).

## Security

- The content script declares `host_permissions` for the Requirement 8 host set only (no
  `<all_urls>`, no `tabs`, no `webNavigation`, no background). It reads meeting URLs on
  those hosts and fires `msteams:` for the real meeting shape only.
- The `msteams:` launch is fired from a Teams-host page, so the browser's "always allow" is
  keyed to that origin (`teams.microsoft.com` in the normal flow), not an arbitrary page or
  the extension. The script is injected on the Requirement 8 host set and acts only on the
  meeting shape. It never runs on other origins.
- The `msteams:` value is bounded on each path. On the web-app path the handler re-validates
  host and path against its regex, so a look-alike host or stray path becomes the Teams home
  page, never a stray meeting window. On the native path the handler forwards every
  `msteams:` URL to `teams-for-linux` unchanged (Decision 4). There it is bounded not by our
  regex but by the `msteams:` prefix (so no `--flag` is read as Electron argv) and by
  `teams-for-linux`'s own `msTeamsProtocols` allow-list. Either way the value is one quoted
  argv element no shell re-parses, and the handler regex rejects whitespace in its tail.
- The `omarchyWebapp` marker guard stops the web-app window's copy of the extension from
  re-firing `msteams:` and looping. It matches the bare token, not `omarchyWebapp=1`
  (Decision 3).
- `/etc/zen/policies/policies.json` force-installs the extension into every Zen profile.
  pacman creates the directory and file at the package's mode (755 dir, 644 root-owned
  file), never through the installer's `chmod a+rw` helper.
- `xpinstall.signatures.required=false` in the Zen policy turns off AMO signature checking
  for every extension in Zen, not only ours. That is the real cost of shipping an unsigned
  XPI. The policy sets it `"Status": "default"`, so a user can restore it (accepting that
  our extension is then disabled at next startup, not only un-updated). The way out if this
  trade-off is rejected is to self-distribution-sign the XPI through AMO. Flagged in
  Decisions for John.

## Design

Data flow:

1. The user clicks a meeting link in the browser.
2. The content script on Microsoft's launcher page rewrites the navigation to
   `msteams://...`.
3. The browser hands it to the desktop. Chromium 151 asks the `xdg-desktop-portal` `OpenURI`
   when the portal runs, `xdg-open` otherwise. Both resolve `x-scheme-handler/msteams`
   through the desktop database.
4. The Omarchy `.desktop` owning `msteams` runs the handler.
5. The handler picks `teams-for-linux` or a web-app window.

### 1. Content script: `default/chromium/extensions/teams-join`

Manifest v3, content-script only, no background, no UI. The `content_scripts` block matches
the Requirement 8 host set (`https://teams.microsoft.com/*`,
`https://teams.cloud.microsoft/*`, `https://teams.live.com/*`,
`https://gov.teams.microsoft.us/*`, `https://dod.teams.microsoft.us/*`,
`https://teams.microsoftonline.cn/*`; no `http://`, no `<all_urls>`) at
`run_at: document_start`, with `host_permissions` for the same hosts. The script:

- Finds either meeting shape (classic `/l/meetup-join/19(:|%3a)...` or short `/meet/<id>`)
  in the launcher `url=` parameter (launcher page only), the page path+query, or a `/v2/`
  URL fragment. It keeps only `p=` and `context=` (Requirement 11) and emits
  `msteams://<page-host>/<path>` (the clicked host is kept; Requirement 10). It assumes
  the `url=` parameter is URL-encoded (so `context`'s own `{`/`"` arrive percent-encoded);
  `searchParams.get` decodes one layer, and the extractor stops only at a fragment or
  whitespace.
- Standalone guard (the origin-independent one). The web-app window is a Chromium `--app`
  window, which reports `display-mode: standalone`. The script stands down there, so it never
  fires in a web-app window regardless of origin, marker, or elapsed time. This closes the
  drift the two guards below cannot: a no-session sign-in that returns on a different Teams
  host after more than 20s (past the throttle, past the per-origin latch). Phase 3 confirms
  standalone distinguishes the web-app window from a normal tab. The marker and latch below
  are the proven fallback where it does not.
- Marker loop guard. If `omarchyWebapp` is a query KEY in the page query, the fragment
  query, or the decoded `url=` value (any form, including `omarchyWebapp%3D1` inside
  `url=`), the script stands down (Decision 3). A `/meet/` id or passcode containing the
  literal token still fires.
- Per-meeting latch. Firing and standing down both latch a per-meeting key in
  `sessionStorage` (per origin per tab). So a later same-origin hop for that meeting does not
  re-fire, while a different meeting in the same tab still can. The observed drift is a
  launcher->`/v2/` hop that drops the marker; the latch covers it. A cross-origin drift
  escapes `sessionStorage`; the handler's ~20s throttle (Design 2) is the origin-independent
  backstop.
- Otherwise it auto-navigates the top frame to the `msteams:` form and latches, so it fires
  at most once per meeting per tab. A manual reload of the launcher page after dismissing the
  prompt does not re-fire for that meeting in that tab. A fresh tab, or a different meeting,
  does.

Core of `content.js`. The marker guard was validated in the Phase 0 spike. The standalone
stand-down is a Phase 3 hand-check. `window.stop()` is settled in Phase 1 Step 0.

```js
// Anchored at a path start so a meeting buried in another page's query cannot
// match. Classic keeps its settled tail (`[^#\s]+` after 19:/19%3a, no /0 or
// meeting_ requirement). Short is meet/<id> with optional ?query; a /extra tail
// stops the match at the id.
function meetingPath(str) {
  if (!str) return null;
  var m = str.match(/^\/(?:l\/meetup-join\/19(?::|%3[aA])[^#\s]+|meet\/[^\/?#\s]+(?:\?[^#\s]*)?)/);
  if (!m) return null;
  var raw = m[0], q = raw.indexOf("?");
  if (q < 0) return raw;
  // Keep only the meeting's own query (p=, context=). Everything else, including
  // unknown future launcher keys, is dropped (Requirement 11).
  var keep = /^(p|context)$/;
  var kept = raw.slice(q + 1).split("&").filter(function (x) { return keep.test(x.split("=")[0]); });
  return kept.length ? raw.slice(0, q) + "?" + kept.join("&") : raw.slice(0, q);
}
// omarchyWebapp as a query KEY in one already-decoded layer, not a substring of
// a path, id, or passcode. URL (not URLSearchParams) because the Node sandbox
// injects only URL.
function hasMarker(layer) {
  if (!layer) return false;
  var q = layer.indexOf("?");
  if (q < 0) return false;
  try { return new URL("https://x/?" + layer.slice(q + 1)).searchParams.has("omarchyWebapp"); }
  catch (e) { return false; }
}
var href = window.location.href;
// Origin- and time-independent guard: the web-app window the handler opens is a Chromium
// --app window, which reports standalone; a normal browser tab does not. Standing down here
// closes the cross-origin / >20s sign-in drift the per-origin latch and the 20s throttle can
// miss. Phase 3 confirms it distinguishes the two; marker + throttle stay as the proven
// fallback for any engine where it does not.
var standalone = false;
try { standalone = window.matchMedia("(display-mode: standalone)").matches; } catch (e) {}
var path = null;
var marker = false;
try {
  var u = new URL(href);
  // Page query, fragment query, and decoded url= (any page: a match can only stand
  // down, which the Security tie-break prefers). searchParams.get decodes one layer
  // so omarchyWebapp%3D1 inside url= still counts.
  marker = hasMarker(u.search) || hasMarker(u.hash) || hasMarker(u.searchParams.get("url") || "");
  if (u.pathname === "/dl/launcher/launcher.html") {
    var v = u.searchParams.get("url") || "";
    path = meetingPath(v) || meetingPath(v.slice(v.indexOf("#") + 1));
  }
  if (!path) path = meetingPath(u.pathname + u.search);
  if (!path && (u.pathname === "/v2/" || u.pathname === "/v2")) {
    path = meetingPath(u.hash.slice(1));
  }
} catch (e) {}
var target = path ? ("msteams://" + u.hostname + path) : null;
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
never reach a `force_installed` (policy-installed) extension on Zen (Phase 0 results,
Decision 1). A content script uses a different injection path that does not depend on the
primed-listener step. Phase 0 confirmed it live on Zen only as a temporary add-on against the
real Teams hosts. Injection from the real `force_installed` `/etc/zen` policy is the one thing
Phase 0 did not test; Phase 1 Step 0 checks it and holds the MV2-for-Zen fallback decision.
The meetup-join URL 302s to the launcher and never commits as a page, so a content script
cannot catch it earlier. It catches it on the launcher page, where the meeting is in the
`url=` parameter.

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

Validates first, then forwards every `msteams:` URL to `teams-for-linux` when present. That
client applies its own `msTeamsProtocols` allow-list, so the regex guards only the web-app
path. Otherwise the handler opens a web-app window on the `https://` meeting URL with the
`omarchyWebapp=1` marker. Validated in Phase 0 (both branches):

```bash
#!/bin/bash
# omarchy:summary=Open Teams meetings from browser protocol links
# omarchy:args=[url]
url="$1"; path=""
# Host alternation is unquoted in =~ so the | branches stay regex. Patterns live
# in variables so a # in the short-shape class cannot start a comment.
hosts='teams\.microsoft\.com|teams\.cloud\.microsoft|teams\.live\.com|gov\.teams\.microsoft\.us|dod\.teams\.microsoft\.us|teams\.microsoftonline\.cn'
hosted_classic="^msteams:/*($hosts)/l/meetup-join/(19(:|%3[aA])[^[:space:]]+)$"
hosted_short="^msteams:/*($hosts)/meet/([^/?#[:space:]]+)(\?[^#[:space:]]*)?(#[^[:space:]]*)?(/[^[:space:]]*)?$"
bare_classic="^msteams:/*l/meetup-join/(19(:|%3[aA])[^[:space:]]+)$"
bare_short="^msteams:/*meet/([^/?#[:space:]]+)(\?[^#[:space:]]*)?(#[^[:space:]]*)?(/[^[:space:]]*)?$"
if [[ $url =~ $hosted_classic ]]; then  # any leading slashes: msteams:teams. .. msteams:///teams.
  host="${BASH_REMATCH[1]}"; path="l/meetup-join/${BASH_REMATCH[2]}"
elif [[ $url =~ $hosted_short ]]; then
  host="${BASH_REMATCH[1]}"; path="meet/${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
elif [[ $url =~ $bare_classic ]]; then  # any leading slashes, host-less: msteams:l/.. msteams:///l/..
  host="teams.microsoft.com"; path="l/meetup-join/${BASH_REMATCH[1]}"
elif [[ $url =~ $bare_short ]]; then
  host="teams.microsoft.com"; path="meet/${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
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

Notes on the handler:

- The web-app window is whichever browser is default. `omarchy-launch-webapp` maps any
  non-Chromium default, Zen included, to `chromium.desktop --app`. So the window loads the
  same `chromium-flags.conf` and the same extension. The `omarchyWebapp` marker (same origin)
  plus the ~20s throttle (any origin) keep it from looping.
- The web-app URL keeps the matched host. The content script emits
  `msteams://<page-host>/...` (Requirement 10), so the handler's host list guards both the
  script's output and external `msteams:` input. A host outside the list lands on the Teams
  home page (fallback only; native forwarding is host-blind).
- The throttle refuses a second web-app window for the same meeting id within ~20s. It sits
  after the native-client branch, so on the native path a cross-origin drift would at worst
  hand `teams-for-linux` the same meeting twice (a duplicate join prompt, not a loop).
  Accepted. Twenty seconds covers a cold Chromium start plus the redirect chain. A re-click
  of the same meeting inside that window is swallowed on purpose.

### 3. Omarchy `.desktop` claims the scheme

`applications/Microsoft Teams Meeting.desktop` (NoDisplay), `Exec=omarchy-webapp-handler-teams %u`,
`MimeType=x-scheme-handler/msteams;`, `Icon=microsoft-teams`. `~/.local/share/applications`
precedes `/usr/share/applications` in the XDG search order. Once the file is in place, the
Omarchy handler beats `teams-for-linux`'s own registration, and the handler's deferral is
the one place that decides.

### 4. Firefox / Zen packaging

`etc/zen/policies/policies.json` (authored in the repo, shipped by `omarchy-settings`) carries:

- Omarchy's Firefox `Preferences` block: the Wayland and media tweaks
  `apz.overscroll.enabled`, `media.ffmpeg.vaapi.enabled`,
  `media.hardware-video-decoding.force-enabled`, `widget.disable-swipe-tracker`, and
  `widget.wayland.fractional-scale.enabled`. These have never been live on Zen, since the old
  installer wrote a path Zen ignores. Moving to `/etc/zen` newly applies them to Zen; Phase 3
  confirms this is benign. Expect `apz.overscroll.enabled` under about:policies > Errors
  (not in Zen's allowed-prefix list). It is pre-existing in `policies.json`, so not a
  regression.
- `xpinstall.signatures.required=false` (`Status: default`, required; see Constraints and
  Security).
- `ExtensionSettings` force-installing the XPI by its `gecko.id`, with `install_url` the
  fixed system path `file:///usr/share/omarchy/default/firefox/teams-join.xpi`, where the
  `default/**` mapping installs it. The XPI ships from `omarchy-settings` too, the same
  package as this policy, so `install_url` can never point at an XPI from a mismatched package
  version. The Phase 0 spike used the worktree path.
- The two keys `zen-browser-bin` already ships in its own `distribution/policies.json`:
  `DisableAppUpdate` (Zen is updated by pacman/AUR, not by itself) and
  `DefaultSerialGuardSetting` (its Web Serial default). They are carried forward because the
  `/etc` file shadows the distribution file that set them. Confirm they still match
  `zen-browser-bin`'s shipped values at implementation, and drop either if the vendor stops
  shipping it.

`omarchy-settings` ships this file package-owned via the repo's `etc/** -> /etc/**` mapping
(`docs/file-layout.md`), the same mechanism behind `/etc/docker/daemon.json` (Decision 8b).
The repo path mirrors the install path, so authoring `etc/zen/policies/policies.json` is the
whole change: pacman places it on upgrade, Zen reads it next start, and no migration,
installer, or `sudo` write is involved. Confirm at implementation that `etc/**` is packaged by
a glob so the new file is picked up automatically; add an explicit PKGBUILD line only if it is
not. The file must NOT be listed in the package's `backup=` array (unlike the package's other
`/etc` drop-ins): `ExtensionSettings` has to track the package, so the shipped version must win on
every upgrade. The cost is that a user's hand-edits to this file are overwritten on the next
`omarchy-settings` upgrade, not preserved as `.pacnew` -- acceptable, since Zen reads a single
policy file with no `.d` merge, so Omarchy owns Zen's whole policy surface regardless.

## Decisions

1. **Content script, not `webNavigation`.** `webNavigation` is dead for `force_installed`
   extensions on Zen (Phase 0 results).
2. **Auto-fire, not a button.** The meeting id survives in the URL only briefly; a click
   loses the race.
3. **Loop guard matches the bare token `omarchyWebapp`.** Microsoft URL-encodes `=1` to
   `%3D1` in the launcher `url=` parameter, so a literal `omarchyWebapp=1` check misses it
   and loops. Seen live in Phase 0 (Phase 0 results).
4. **Forward every `msteams:` URL to `teams-for-linux` when installed.** The strict check
   bought no security on that path and regressed non-meeting deep links.
5. **Set the signing pref via the Zen policy.** This build's effective default is true
   (Constraints).
6. **Commit the XPI with a source-pin test.**
7. **Signing pref `Status: default`, not `locked`.** Disabling AMO checking is a real cost, so
   let the user restore it. If that trade-off is rejected, AMO self-distribution signing is
   the alternative. Open for John.
8. **Zen policy delivery. Decided: (b), package-owned drop-in (2026-09-07).**
   - Options:
     - (a) The migration and installer write `/etc/zen/policies/policies.json` with
       `sudo install -D` (the earlier plan).
     - (b) Ship the file from the `omarchy-settings` package via the repo's
       `etc/** -> /etc/**` mapping, the same path as `/etc/docker/daemon.json` and the other
       `/etc` drop-ins this repo already carries.
   - What (b) removes: the migration's Zen step, the installer write, the
     `omarchy-remove-browser` cleanup, the fake-`sudo` test, A7's sudo accounting, and the
     non-wheel-user failure mode. pacman drops the file on `omarchy-settings` upgrade, Zen
     reads it next start, nothing else touches `/etc/zen`.
   - Overwrite safety: (b) cannot silently clobber a user's own Zen policy. Omarchy has
     never written to `/etc/zen/policies/`; its current Zen policy goes to
     `/opt/zen-browser/distribution/policies.json` (a separate path, and a broken one --
     Zen reads `/etc/zen/policies/` via `MOZ_SYSTEM_POLICIES`), so no existing Omarchy file
     collides. If a user hand-placed a policy there, pacman refuses to overwrite an unowned
     file: it halts the `omarchy-settings` upgrade with `exists in filesystem, owned by no
     package` rather than replacing it. Contrast (a): `sudo install`/`cp -f` overwrites a
     hand-rolled policy silently, so (b) is the safer of the two here. Caveat common to both:
     `/etc/zen/policies/policies.json` is a single file (Gecko has no `.d` merge for
     policies), so Omarchy owns Zen's whole policy surface either way. The file is not a pacman
     `backup=` file (`ExtensionSettings` must track the package, so the shipped version wins on
     upgrade), so a user's hand-edits to it are overwritten on the next `omarchy-settings`
     upgrade, not preserved as `.pacnew`.
   - What (b) costs: a 1KB inert file on non-Zen boxes, and pre-cleaning any unowned
     `/etc/zen/policies/policies.json` before the upgrade (the Phase 0 residue on the dev box;
     general users hit this only if they hand-placed a policy). An empty `/etc/zen` dir does
     not block pacman -- only an unowned file at the target path does. Do not paper over that
     block by adding `/etc/zen/*` to `bin/omarchy-update-system-pkgs`'s `--overwrite` (scoped
     to `/usr/share/omarchy/*` today); the refusal is the never-clobber behavior we want.
     Blast radius: `omarchy` pins `omarchy-settings=<version>`, so a halted `omarchy-settings`
     upgrade blocks the whole Omarchy update with a raw pacman error until the unowned file is
     cleared.
   - Decided: (b). Phase 3 shrinks to the XPI, the policy file, the pin test, and the
     hand-checks; the migration, installer, and `omarchy-remove-browser` Zen steps and their
     tests drop. The policy is authored at `etc/zen/policies/policies.json` (repo path mirrors
     the install path) and reaches `/etc/zen/policies/policies.json` through the `etc/**`
     mapping.

## Extension: every meeting format, every cloud

Added 2026-09-07 after a real `/meet/<id>?p=<passcode>` link did not fire under the design
above. Source: `teams-url-formats-research.md` (live-verified 2026-09-07 against Microsoft's
launcher JS, MS Learn, and teams-for-linux v2.20.0). This section amends the Requirements,
Acceptance criteria, Non-goals, Constraints, Security, and Decisions above. It states WHAT
changes. The Plan owns HOW.

### Problem

The design above recognises one meeting shape (`/l/meetup-join/19(:|%3a)...@thread.v2`) on
three commercial hosts, and rebuilds every match to `msteams://teams.microsoft.com/...`.
Three facts break that:

1. Microsoft's default meeting link is now the short form `/meet/<meetingId>?p=<passcode>`.
   Meet-now has used it since Feb 2025. Scheduled meetings since Jan 2026 (commercial and
   GCC) and Feb 2026 (GCC High and DoD). New invites will carry this shape, not the classic
   one. A user's real `/meet/` link opened in a browser tab and stayed there.
2. Teams runs in more than one cloud. GCC High lives on `gov.teams.microsoft.us`, DoD on
   `dod.teams.microsoft.us` (thread ids `19:dod:meeting_...`), consumer on `teams.live.com`.
   The gov and DoD hosts never inject the script today (`teams.live.com` already does), and a
   gov meeting forced onto `teams.microsoft.com` is the wrong cloud.
3. The launcher intermediary `/dl/launcher/launcher.html?url=<encoded /_#/deeplink>` carries
   either shape inside `url=`. Design 1 handles it for the classic shape only.

A meeting link must open in the client whatever its shape and whatever its cloud.

### Requirements (continues the list above)

7. **Two meeting shapes.** The extension and the handler recognise both:
   - Classic: the settled Design 1 shape `l/meetup-join/19(:|%3a)<tail>` -- any non-whitespace
     tail, NO `/0` or `meeting_` requirement, matching the current handler and content script.
     `<tail>` commonly carries `19:meeting_<id>@thread.v2` (or `19:dod:meeting_<id>@thread.v2`)
     then `/0?context=`, but ALSO channel-meeting forms (`19:<id>@thread.tacv2`, legacy
     `@thread.skype`) with a message id in place of `0`. Those are examples, not bounds. `:`
     and `@` may arrive as `%3a`/`%40`. (Verify a live channel-meeting link during
     implementation; the research pinned `/0` and did not cover channel meetings.)
   - Short: `meet/<meetingId>`, with optional `?p=<passcode>`. `<meetingId>` is any run of
     characters that is not `/`, `?`, `#`, or whitespace. It is NOT digits-only: Microsoft's
     own tests accept `meet/user@example.com`. `p` may be absent (consumer links). A trailing
     `/extra` after the id matches on the id (the tail is ignored, as the classic shape
     tolerates a tail).
8. **Five hosts, one best-effort.** Both shapes are recognised on `teams.microsoft.com`,
   `teams.cloud.microsoft`, `teams.live.com`, `gov.teams.microsoft.us`, and
   `dod.teams.microsoft.us`. `teams.microsoftonline.cn` (21Vianet) is included best-effort
   and flagged unverified (Decision 12). Bare `teams.microsoft.us` is not a web host and is
   not matched.
9. **Launcher intermediary.** The `url=` parameter is a meeting source ONLY on the launcher
   page `/dl/launcher/launcher.html`. There, decode `url=` and match the meeting shape
   (Requirement 7) inside it; the shape decides. There is NO separate `type` gate -- a
   non-meeting `url=` payload fails the shape check, and the launcher's `type` may be absent
   (so a `type` gate would silently break a real join). The script fires once on the extracted
   meeting, not on the launcher URL itself. Because `url=` is read only on the launcher page,
   `/convene/meetings?url=<meeting>` (a different page) is never a source.
10. **Preserve the cloud in what Omarchy emits.** The emitted `msteams:` URL names the host
    the user clicked, and the web-app fallback opens `https://<original-host>/<path>`. Omarchy
    never rewrites a gov, DoD, consumer, or `cloud.microsoft` host to `teams.microsoft.com`.
    What `teams-for-linux` then does with a gov/DoD host is its own concern (Decision 9): the
    guarantee covers what Omarchy emits and what the fallback opens, not the client's routing.
11. **Query handling -- allow-list contract (content script).** The URL the CONTENT SCRIPT
    emits keeps ONLY the meeting's own `p=` and `context=`; every other query parameter is
    dropped, so an unknown future launcher key is dropped by default. This exact kept-set is the
    contract, and the tests include an unknown-key case (A15). It matches Design 1's observed
    output on real inputs: a classic launcher URL carries only `context=` once the launcher's
    `anon`, `deeplinkId`, `launchAgent`, `enablemcas`, `suppressPrompt` and routing keys
    (`type`, `directDl`, `msLaunch`, `enableMobilePage`, `fqdn`) are gone. The Plan achieves
    "only `p=` and `context=` survive" with an allow-list filter (extending Design 1's drop-list
    qualifies only if it provably covers every key the launcher can add). This is the content
    script's job; the handler does NOT add a second allow-list -- it passes an external
    `msteams:` (e.g. from Outlook, with extra keys) through to `teams-for-linux` unchanged
    (Decision 4). The host carries the cloud, so `fqdn` is dropped and not needed.
12. **Both shapes reach both targets.** With `teams-for-linux` installed, both shapes reach it
    unchanged (Decision 4 stands, subject to Decision 11). Without it, both shapes open a
    web-app window on the original host with the `omarchyWebapp=1` marker, under the same
    throttle.

Edits to existing text this implies (the Plan applies them):

- Requirement 1: the shape and host list become "either shape in Requirement 7 on any host
  in Requirement 8".
- A5.1: "a recognised meeting URL" means either shape (Requirement 7) with a listed host
  (Requirement 8) OR in the host-less v1 form `msteams:/<path>` that settled Design 2 already
  accepts; the host-less web-app fallback keeps today's default host `teams.microsoft.com`.
- A8: replace "the three Teams hosts" with the Requirement 8 host set, and replace "the page
  host is dropped" with "the page host is kept". A8 also covers the `/meet/` shape.
- Constraints and Security: every "three Teams hosts" becomes the Requirement 8 host set, and
  the Constraints prompt bound "up to three" times becomes "up to the size of the host set".
- Design 1 and Design 2 notes that say the script "always rebuilds to `teams.microsoft.com`"
  are superseded by Requirement 10.
- Requirement 2's "No configuration beyond installing `teams-for-linux`" is scoped to the
  commercial and consumer clouds; a GCC High or DoD user must also point `teams-for-linux` at
  their cloud in its own config (A9, Decision 9). The web-app fallback needs no configuration
  on any cloud.

### Non-goals (updated)

The old non-goal line "Personal-account `teams.live.com/meet/<id>` links" is removed; both
`/meet/` and `teams.live.com/meet` are in scope now (Requirements 7 and 8). Add:

- Firing on a web-client destination that carries no meeting. `/light-meetings/launch` has no
  meeting in its URL, and a `/v2/?meetingjoin=true#/...` URL with no recognised meeting path in
  the fragment does not fire. A `/v2/` fragment that DOES carry a recognised `/l/meetup-join/`
  or `/meet/` path is a meeting under settled A8 and Design 1 and fires on first contact -- the
  per-meeting latch only blocks the REPEAT after the launcher hop, it does not create that
  first fire. So the non-goal is "a `/v2/` URL with no recognised meeting path", not "every
  `/v2/` URL". (This narrows research item E, which lists all `/v2/` as non-firing; the
  fragment-carries-meeting case is a deliberate, A8-consistent deviation from the research.)
- Town hall and broadcast attendee pages, `/convene/meetings?url=...`. Microsoft routes them
  to the web. They stay web (Decision 10).
- The scheduling dialog `/l/meeting/new`. It creates a meeting; it is not a join.
- Non-meeting deep links under `/l/`: `chat`, `call`, `channel`, `team`, `message`,
  `entity`, `app`, `task`, `file`, `meeting-share`. Requirement 5 still forwards them to
  `teams-for-linux` when a client emits them as `msteams:`; the browser extension never
  turns their `https://` form into `msteams:`.
- Safe Links wrappers (`<region>.safelinks.protection.outlook.com/?url=...`). The browser
  follows the redirect and lands on the real Teams host, where the script runs. No handling.
- The `ms-teams:` scheme. The launcher uses it only for consumer links on a Windows user
  agent. Linux never sees it. `teams-for-linux` does not register it either.
- Verifying the 21Vianet cloud. It is unreachable from the US. Its host is matched
  best-effort; its link shapes are not confirmed (Decision 12).
- Fixing `teams-for-linux`'s own cloud routing. A GCC High or DoD user must point
  `teams-for-linux` at their cloud in its own config. Our URL cannot do that for them
  (Decision 9).

### Acceptance criteria (continues A1-A8)

- A9. A `/meet/<id>` link on each of the five verified hosts in Requirement 8 fires, whether
  or not it carries `?p=<passcode>` (consumer Meet-now links omit it). With `teams-for-linux`
  installed it reaches the client (on gov/DoD this opens the meeting only when the user's
  `teams-for-linux` is configured for that cloud, Decision 9); without it, a web-app window
  opens on the meeting. When `p=` is present it arrives unchanged at whichever target opens;
  when absent, none is synthesized. One fire per meeting per tab, per A8.
- A10. A classic link on `gov.teams.microsoft.us` or `dod.teams.microsoft.us`, including a
  `19:dod:meeting_...` thread id, fires. The `msteams:` URL the content script emits and the
  web-app fallback both stay on the clicked host; Omarchy never substitutes `teams.microsoft.com`
  there. ("Emitted" is the content-script URL; whether the handler translates it on the native
  path is Decision 11.) The web-app fallback opens the correct cloud unconditionally; the native
  client's cloud follows the user's `teams-for-linux` config on gov/DoD (Decision 9).
- A11. For each of the five verified hosts in Requirement 8, the web-app fallback opens
  `https://<original-host>/<path>` plus the `omarchyWebapp=1` marker, for both shapes. The
  handler accepts an `msteams:` URL that names any listed host (the Requirement 8 set as
  Decision 12 settles it) and the host-less v1 form `msteams:/<path>` settled Design 2 already takes (its
  web-app fallback uses the default host `teams.microsoft.com`). On the WEB-APP FALLBACK path
  (no `teams-for-linux`), a host outside the list lands on the Teams home page (the look-alike
  rule in Security). This host validation is fallback-only: with `teams-for-linux` installed,
  Decision 4 still forwards every `msteams:` URL unchanged, unlisted host included, so host
  checking must not move ahead of native forwarding (that would regress Requirement 5).
- A12. None of these fire: a `/v2/?meetingjoin=true#/...` URL whose fragment carries NO
  recognised meeting path (a fragment that DOES carry a `/l/meetup-join/` or `/meet/` path
  fires per A8 -- it is not a negative), `/light-meetings/launch`, `/convene/meetings`,
  `/l/meeting/new`, and every non-meeting `/l/<type>/` in the Non-goals list. Tested on at least
  one commercial host and one gov host.
- A13. A launcher URL `/dl/launcher/launcher.html?url=<encoded meeting>` fires exactly once,
  on the meeting extracted from `url=` (whatever the `type`, or none), with the launcher
  parameters dropped and `p=`/`context=` kept. A launcher `url=` carrying a NON-meeting path
  (chat/channel/call) does not fire -- the shape check excludes it, not a type gate. `url=` on
  any page other than the launcher (e.g. `/convene/meetings?url=<meeting>`) is not read, so it
  does not fire.
- A14. The loop guard holds for the new shapes and hosts. The `omarchyWebapp` marker, the
  standalone guard, the per-meeting latch, and the ~20s throttle each treat a `/meet/`
  meeting the way they treat a classic one. A `/meet/` id and a classic thread id for the
  same meeting are different keys; unifying them is not required. Two encodings of one id --
  classic or short (a `/meet/` id can contain `@`, folded from `%40`) -- still map to one key
  on every host. The throttle keeps its settled host-independent key (id only), which is what
  catches the `teams.microsoft.com` -> `teams.cloud.microsoft` cross-origin hop for one meeting.
  The theoretical collision -- the same `/meet/` id issued by two different clouds and both
  clicked within ~20s -- is accepted: meeting ids are per-cloud generated, so it does not arise
  in practice, and adding a cloud class to the key would cost that cross-origin backstop. (grok
  and Sol split on this; keeping the settled key is the simpler correct call.)
- A15. `./test/all` covers each of the five verified hosts for both shapes, the A12 negatives,
  and the launcher intermediary firing on a valid embedded meeting -- with at least one launcher
  case on a gov/DoD host asserting the emitted `msteams:` host and the web-app fallback host
  stay on that cloud (so launcher extraction cannot be hard-coded to `teams.microsoft.com`). At
  least one classic case is a CHANNEL meeting (`@thread.tacv2`, a message id in place of `0`,
  per Requirement 7), so the matcher is not narrowed to `meeting_...@thread.v2/0`. At least one
  `/meet/` case uses a non-numeric id (e.g. `user@example.com`), so a digits-only short matcher
  fails. A `/meet/` case with `p=` asserts the passcode arrives unchanged and never lands in the
  throttle stamp or the latch key; a `/meet/` case without `p=` asserts it still fires and none
  is synthesized (A9 and Security). An unknown extra query key (not `p=`/`context=`) is dropped
  from the emitted URL (Requirement 11). Two exclusion negatives prove the launcher mechanism,
  each carrying a VALID embedded `/meet/` or `/l/meetup-join/` payload: a
  `/convene/meetings?url=<meeting>` case (proves `url=` is read only on the launcher page, not
  `/convene/`), and a launcher `url=` carrying a NON-meeting path (proves the shape check, not a
  `type` gate, excludes it). A meeting whose `/meet/` id or passcode contains the literal
  `omarchyWebapp` token still fires (marker-scoping in Security). The manifest test asserts the
  `content_scripts.matches` and `host_permissions` sets equal the Requirement 8 host set as
  Decision 12 settles it (21Vianet in or out per that decision), still `https://` only, still no
  `<all_urls>`.

### Decisions (continues 1-8)

9. **Preserve the original cloud (Requirement 10). Recommended: yes. Open for John.**
   - The clicked host reaches the client and the fallback unchanged. A DoD meeting never
     becomes a `teams.microsoft.com` URL.
   - Documented limitation, not a blocker: `teams-for-linux` v2.20.0 recognises only the three
     commercial hosts in its `msteams://<host>/` matching, and its host-less form loads the
     path against its own configured `config.url` (default `teams.cloud.microsoft`). So a GCC
     High or DoD user must set `teams-for-linux`'s URL (and, for the host form, its
     `msTeamsProtocols`) to their cloud in ITS config. Our rewrite cannot fix that from the
     URL. Preserving the host costs nothing on the commercial path and makes the gov path
     correct once the user's own client is configured; forcing commercial would make it wrong
     on every path.
   - A5.2's home fallback (no `teams-for-linux`, unrecognised `msteams:` input) stays
     `https://teams.microsoft.com/`. A host-less non-meeting URL carries no cloud to preserve.
     Accepted.
10. **Town hall and broadcast `/convene/` links stay web. Recommended: do not fire. Open for
    John.** Microsoft itself routes attendees to a web page for these. Whether the client
    should ever open them is unconfirmed. Firing a scheme on a page Microsoft treats as web
    risks a client that lands on nothing. Revisit only on a real report.
11. **Emitted form is v2 (host-preserving); native path forwards it UNCHANGED. Decided.**
    The content script emits `msteams://<host>/<path>` (A10 requires the clicked host; host-less
    v1 carries no cloud for the fallback). On the native path the handler forwards it to
    `teams-for-linux` UNCHANGED for every host -- Decision 4 survives and the handler stays
    host-blind (consistent with A11: host validation is fallback-only). Consequences from the
    research: `teams-for-linux` v2.20.0's v2 regex accepts `teams.microsoft.com`,
    `teams.live.com`, `teams.cloud.microsoft` (correct cloud opens) and REJECTS gov/DoD/cn, so a
    gov/DoD/cn user on the client's default config gets a LOUD no-op (nothing opens) and must
    point `teams-for-linux` at their cloud in its own config (Decision 9, A9) -- required
    regardless of what we emit. We deliberately do NOT translate to host-less v1: v1 loads every
    link against the client's single `config.url`, silently opening a consumer or gov meeting in
    the WRONG (commercial) cloud, and a silent wrong-cloud join is worse than a loud no-op;
    translating would also put host logic on the native path, contradicting A11 and ending
    Decision 4. The web-app fallback preserves the host regardless. (Resolved 2026-09-07 from the
    earlier per-host/translation framing.)
12. **21Vianet host, best-effort. Recommended: include in the host set, flag unverified, no
    acceptance criterion. Open for John.** Cost: one more host pattern in the manifest and
    handler, and one more possible "open msteams?" prompt. Risk: none new, since the script
    fires only on the two meeting shapes. If the cloud's link shapes differ, the script does
    nothing there, which is today's behaviour. The alternative is to leave it out until a user
    asks. Either is fine; include is the smaller later change. Native routing for a matched
    `.cn` link follows the same best-effort as gov/DoD (Decision 11): `teams-for-linux`'s v2
    regex excludes `teams.microsoftonline.cn` too, so the Plan either keeps it host-ful,
    translates to v1, or relies on the user's client override -- no acceptance criterion, same
    as its shape verification.

### Constraints and Security notes (deltas)

- **Wider host set.** `content_scripts.matches` and `host_permissions` grow from three hosts
  to the Requirement 8 set (five, six with 21Vianet). Still exact `https://` hosts, still no
  `<all_urls>`, still no `tabs`, `webNavigation`, or background. On the web-app fallback path
  the handler's host allow-list grows to the same set and still rejects anything else, so a
  look-alike host becomes the home page, never a meeting window; the native path forwards every
  `msteams:` unchanged (Decision 4), so this host check is fallback-only (A11).
- **More one-time prompts.** The browser's "always allow" is keyed per origin. A user who
  meets links on several clouds sees the prompt once per host they hit, up to the size of the
  host set. Same behaviour as today, larger bound. Not ours to suppress.
- **Marker recognition vs arbitrary short ids.** Design 1's loop guard stands down when it sees
  the `omarchyWebapp` marker. A `/meet/` id or passcode is arbitrary (Requirement 7), so a bare
  substring match could false-stand-down on a meeting whose id contained that literal token.
  WHAT the check must do: recognise `omarchyWebapp` as a query KEY in whatever layer it sits --
  the page query, the decoded `url=` value, or the fragment query -- after decoding that layer.
  (Inside an encoded `url=` the delimiters are `%3F`/`%26`, so a raw key-match and a bare
  `omarchyWebapp%3D1` substring both fail; decode first.) It must not match the token as a
  substring of a path, id, or passcode. Tie-break if the layering is ever ambiguous: a false
  stand-down (a real meeting not opening) is preferred over a false fire, since the false fire
  is the Phase 0 loop bug and the collision is a synthetic id. A15 adds a collision case.
- **The `p=` passcode in the URL.** `p=` is the hashed meeting passcode Microsoft puts in the
  shareable link. Anyone holding the link already holds it, and it already travels through the
  browser's history and the launcher URL. Carrying it into `msteams:` and the fallback URL
  adds no new exposure. Two rules keep it that way:
  - The handler's throttle stamp stores the meeting id only, never the query. `p=` must not
    land in `~/.local/state`.
  - The per-meeting `sessionStorage` latch keys on the path with the query stripped, as
    Design 1 does today. `p=` must not land in the latch key.
- **Short-shape id is bounded.** `<meetingId>` excludes `/`, `?`, `#`, and whitespace, so the
  handler's tail guard still rejects whitespace and the value stays one quoted argv element no
  shell re-parses. `@` in a meeting id (the `user@example.com` case) is allowed and carries no
  shell meaning.
- **Native path unchanged.** Every `msteams:` URL still goes to `teams-for-linux` unchanged
  when installed (Decision 4, subject to Decision 11). Its own `msTeamsProtocols` allow-list
  bounds the value there, as before.

### Review log (extension gate)

| Gate | Stage | Round | Findings | Integrated |
|------|-------|-------|----------|------------|
| spec addition | grok-review | 1 | 5 (0 P1, 3 P2, 2 P3) | 5; Decision 11 reframed (A10+Req11 already rule out host-less v1 -> emit v2, native-path translation open); A11/A15 narrowed to 5 verified hosts (21Vianet membership only); A9 covers no-passcode /meet/; A14 folds /meet/ id encoding; A15 negatives point at A12/A13 |
| spec addition | grok-review | 2 | 3 (0 P1, 2 P2, 1 P3) | 3; scoped Req10/A9/A10 to what Omarchy emits + fallback, qualified native gov/DoD with Decision 9 (teams-for-linux can't do both host-preserve and gov/DoD open); A15 requires a non-numeric /meet/ id case; Req11 drop-list marked non-exhaustive, Plan pins vs launcher JS |
| spec addition | grok-review | 3 (cap) | 6 (0 P1, 3 P2, 3 P3) | 6; extension-vs-settled-base consistency: /v2/ non-goal narrowed (a /v2/ fragment carrying a meeting still fires per A8, latch only blocks the repeat); A5.1/A11 keep the host-less v1 form Design 2 accepts; A15 pins the p= security rules; A10 "emitted"=content-script URL (Decision 11 owns native argv); Req11 = Design 1 blacklist not keep-only; Constraints "up to three" prompt bound in the edit list. Cap reached |
| spec addition | codex-review (Sol, gpt-5.6-sol) | 1 | 4 (0 P1, 4 P2) | 4; A12 /v2/ negative narrowed to fragments with no meeting (matches A8); Decision 11 now per-host (global v1 would regress teams.live.com consumer + non-config.url clouds -- tfl v2 accepts commercial+consumer, rejects gov/DoD); A15 adds a gov/DoD launcher case asserting host preservation; Req11 settled the kept-set contract {p,context}, HOW open |
| spec addition | codex-review (Sol) | 2 | 4 (0 P1, 3 P2, 1 P3) | 4; marker check must scope to the marker query param (a /meet/ id/passcode containing "omarchyWebapp" must still fire) + collision test; Req11 -> ALLOW-LIST (resolves grok-blacklist vs codex-exact-set: allow-list required for an exact testable contract) + unknown-key test; exclusion tests must embed a valid meeting in url= (bare /convene/ proves nothing); Problem: only gov/DoD newly non-injecting (teams.live.com already injects) |
| spec addition | codex-review (Sol) | 3 (cap) | 4 (0 P1, 4 P2) | 4; Req2 "no config" scoped to commercial/consumer (gov/DoD need client config, A9/Dec9); A11 + Security host-rejection is FALLBACK-ONLY (native forwards every msteams unchanged, Dec4, or regresses Req5); A14 throttle identity is cloud-aware ({microsoft.com,cloud.microsoft} one class, live/gov/dod/cn distinct -- same id on distinct clouds both fire); Decision 12 gives .cn the same best-effort native routing as gov/DoD. Cap reached |
| spec addition | claude-review (fable-5, single) | 1 | 11 (3 major, 8 nit) | 11; MAJOR: Req7 classic shape loosened to settled breadth (Req7 as written regressed CHANNEL meetings @thread.tacv2/@thread.skype with msgid != 0 -- verified live); launcher type-gate DROPPED (redundant + fragile: a type-less launcher URL would silently break joins; url= is a source only on the /dl/launcher/ page, which is what excludes /convene/); Decision 11 RESOLVED to forward-v2-unchanged (Dec4 survives, handler host-blind; gov/DoD get a loud no-op, better than v1's silent wrong-cloud join). Nits: reverted A14 to the settled host-independent throttle (codex's cloud-aware key guards a synthetic collision -- grok/Sol vs fable, adjudicated to simple); marker WHAT-framing + tie-break; Req11 content-script-scoped (handler adds no 2nd allow-list); 21Vianet as "Requirement 8 set per Decision 12"; /v2 research-deviation noted; stale Req5 edit item removed. TO-DO: verify a live channel-meeting link shape in implementation |


## Plan

Branch from `origin/quattro`. No dependency on PR 10367.

### Phase 0. Spike — DONE (2026-09-07)

Confirmed the hook and the fallback end to end (see Phase 0 results). No code from the spike
is kept; the spike extension lived in the session scratchpad.

### Phase 1. Handler, `.desktop`, and icon (tests first)

Step 0, before any test code: settle the two residuals that can fork the design.

1. Injection under policy. On a fresh Zen profile with the real `force_installed` `/etc/zen`
   policy and a zipped Phase 0 content script, confirm the script injects on the launcher
   page. Temporary add-ons auto-grant host permissions, so Phase 0 is no evidence for the
   policy path. If it injects, proceed MV3. If not, decide the MV2-for-Zen fork now: an MV2
   XPI for Zen breaks the one-source-tree design and the pin test. That decision is on record
   before Phase 1 code.
2. `window.stop()`. In the same spike, confirm `window.stop()` after the `msteams:` assign
   does not cancel the launch on either engine. At `document_start` it can leave a blank tab
   and may race the launch. Keep it only if the launch fires every time (a blank leftover tab
   is acceptable). Else drop it from Design 1 and the tests.

**Step 0 result (2026-09-07, John-run on Zen 1.22b): both PASS.** A fresh Zen profile with
the real `force_installed` `/etc/zen/policies/policies.json` (the reviewed content script,
zipped, unsigned, `Status: default` signing pref) injected the content script on the Teams
host -- so the policy install path is not the broken one Phase 0 saw for `webNavigation`.
**MV3 stands; the MV2-for-Zen fork is closed.** With `teams-for-linux` absent, a real meeting
fired `msteams:` through the content script and our handler opened the web-app window on the
meeting, so `window.stop()` did not cancel the launch: **keep `window.stop()`** (no change to
Design 1 or the tests). Tested against the real Omarchy Teams web app (PR omacom/omarchy#10367)
and our Phase 1 handler, not a stub. Side result: that PR's web app confirms the installed
icon name is `microsoft-teams` (from the `homarr-labs/dashboard-icons` CDN), matching our
`.desktop`'s `Icon=microsoft-teams` -- the Phase 1 icon-name open item is settled; only the
real PNG asset remains.

Files:

- `bin/omarchy-webapp-handler-teams`
- `applications/Microsoft Teams Meeting.desktop`
- `applications/icons/Microsoft Teams.png`. Source icons are Title-Case like
  `Google Messages.png`; `omarchy-settings` installs them lowercase-dashed into hicolor, so
  `Icon=microsoft-teams` resolves. Confirm the installed name against the `omarchy-settings`
  PKGBUILD, which is not in this repo.
- `test/shell.d/webapp-handler-teams-test.sh`

Test setup:

- Fake `omarchy-launch-webapp`, `setsid`, and `uwsm-app` on `PATH`.
- A fake `teams-for-linux` added or omitted. The handler resolves it through
  `omarchy-cmd-present`, a `command -v` loop, so `PATH` is the whole mechanism.
- `XDG_STATE_HOME` pointed at a fresh temp dir per case, so the throttle and the real
  `~/.local/state` are never touched.

Cases:

- Each A5 shape, with and without `teams-for-linux`.
- The marker joined with `&`/`?` and placed before any fragment.
- Look-alike host and non-meeting go to the home page.
- Throttle:
  - The same meeting id twice inside the window opens once (the second call exits 0 with no
    `omarchy-launch-webapp`).
  - The same id after the window opens again.
  - A different id always opens.
  - Two encodings of one id (`%3a`/`%40` vs `:`/`@`) count as the same.
  - An empty or one-field stamp opens.

`.desktop` assertions (no existing test reads `applications/*.desktop` content, so a typo
ships silently otherwise):

- `MimeType=x-scheme-handler/msteams;`
- `Exec=omarchy-webapp-handler-teams %u`
- `NoDisplay=true`
- `Icon=` equals the lowercase-dashed name of a PNG in `applications/icons/`.

### Phase 2. Content-script extension, Chromium wiring, migration (tests first)

Files:

- `default/chromium/extensions/teams-join/{manifest.json,content.js}`
- `config/chromium-flags.conf`
- `migrations/<epoch>.sh`
- `test/shell.d/chromium-teams-join-test.sh`
- `test/shell.d/teams-join-migration-test.sh`

The migration, each step idempotent:

1. Copy the `.desktop` into `~/.local/share/applications/` if absent or different. Then run
   `update-desktop-database ~/.local/share/applications` unconditionally (cheap and
   idempotent) so `mimeinfo.cache` learns the handler; copying the file alone leaves the
   scheme unresolved. This is a narrow copy, not `omarchy-refresh-applications`, which
   re-copies every shipped `.desktop` (overwriting user edits) and runs
   `install/user/mise.sh`.
2. Add `extensions/teams-join` to `--load-extension=` in each flags file. Iterate the browser
   list from the whatsapp-slim migration plus `brave-origin` (the installer writes
   `brave-origin-flags.conf`, which that loop's `brave-origin-beta` misses). Then echo
   "restart Chromium/Brave to load the Teams extension", since the flags edit only applies on
   the next browser start.
3. No Zen policy step. The policy ships as a package-owned file via `omarchy-settings`
   (Decision 8b), not through the migration; Phase 3 covers the policy file and XPI.

Tests:

- Manifest test asserts: MV3; `content_scripts.matches` equals exactly the `https://` host
  patterns (three at Phase 2; widened to the Requirement 8 set in Phase 4) (no `http://`, no
  `<all_urls>`); `host_permissions` for the same set;
  `run_at: document_start`; no `webNavigation`/`tabs`/background; non-empty `gecko.id`.
- A `run_node_test` behaviour test runs `content.js` with `vm.runInNewContext`. It uses a
  fresh sandbox per case, since Node 26 ships a native `sessionStorage` global and a direct
  `eval` lets the script's `var`s clobber the harness. It stubs `window.location`,
  `sessionStorage`, `matchMedia`, and `window.stop`, and asserts:
  - A meeting URL (each host, `:` and `%3a` forms, the v2 fragment form, a single-encoded
    `context=` in the `url=` param, and a `deeplinkId=` before `context=`) rewrites to
    `msteams://teams.microsoft.com` + path for all three page hosts (the page host is always
    dropped), with `context` kept.
  - A URL carrying `omarchyWebapp=1` and its `omarchyWebapp%3D1` encoded form both stand
    down and latch the tab (a following marker-less `/v2/` hop in the same tab does not
    fire).
  - A `matchMedia('(display-mode: standalone)')` stub returning `matches: true` yields no
    fire.
  - A non-meeting URL and any repeat in the same tab do not fire.
  - A stubbed `window.stop` is called after a fire and not on a stand-down.
- Flags drift test.
- Migration test, modelled on the tmux one: run twice, asserting one flags entry and one
  `.desktop` per run, one `update-desktop-database` call per run, and the `brave-origin`
  entry. It stubs `update-desktop-database` on `PATH` so `./test/all` never runs a real
  system write. The migration has no Zen policy step under (b), so there is no Zen case here.

### Phase 3. Zen wiring and end-to-end check (tests first)

Files:

- `etc/zen/policies/policies.json` (authored here; `omarchy-settings` ships it to
  `/etc/zen/policies/policies.json` through the `etc/**` mapping, Decision 8b).
- `default/firefox/teams-join.xpi` (shipped by `omarchy-settings` via `default/**` to
  `/usr/share/omarchy/default/firefox/`, which the policy's `install_url` points at -- same
  package as the policy).
- No `omarchy-install-browser`, `omarchy-remove-browser`, or PKGBUILD change if `etc/**` is
  already packaged by a glob (verify; add one PKGBUILD line only if it is an explicit list).
  pacman owns the file, so it lands on upgrade and is removed when the package stops shipping
  it. Do not add it to the package's `backup=` array (Decision 8b). A pre-existing unowned
  `/etc/zen/policies/policies.json` (Phase 0 residue, or a hand-rolled policy) blocks the
  upgrade until cleared, rather than being overwritten (Decision 8).
- `test/shell.d/firefox-teams-join-test.sh`
- No `docs/file-layout.md` row: the existing `etc/** -> /etc/**` row already covers it.

Tests in `firefox-teams-join-test.sh`:

- Policy and XPI test (python3, zipfile + json), reading `etc/zen/policies/policies.json`
  and the XPI directly (no migration or installer to exercise under (b)):
  - The `ExtensionSettings` key equals `gecko.id`, and its `installation_mode` is exactly
    `force_installed` (not `normal_installed`, missing, or hyphenated, any of which would
    silently not force-install).
  - `install_url` equals `file:///usr/share/omarchy/default/firefox/teams-join.xpi` exactly
    (not only contains `teams-join.xpi`).
  - The Zen policy's `Preferences` is a superset of `default/firefox/policies.json`'s
    `Preferences`, adding exactly `xpinstall.signatures.required` = `{Value: false, Status:
    default}` (a Firefox preference, set inside `Preferences`, not a top-level policy key).
  - The only top-level `policies` keys beyond `Preferences` are `ExtensionSettings`,
    `DisableAppUpdate`, and `DefaultSerialGuardSetting`.
  - `default/firefox/policies.json` (the Firefox policy) has no `ExtensionSettings`.
  - The XPI member names equal the source file names as a set, and each member's bytes
    match.
  - Version bump, so an edit cannot ship without the version bump Zen needs to reinstall.
    The test compares `manifest.version` against the base manifest at
    `${TEST_GIT_UPSTREAM:-origin/quattro}`
    (`git show <base>:default/chromium/extensions/teams-join/manifest.json`, borrowing the
    variable name from `test/shell.d/update-available-test.sh`, `none` to skip) whenever the
    tracked `content.js`/`manifest.json` differ from that base. It fails with a "bump the
    version" message when they differ but the version does not. A missing base (this branch
    before merge, or a checkout without the ref) is a new extension: pass, running only the
    XPI byte-match. The test `require_command git`, since it is otherwise python-only. A bare
    sha256 pin would not enforce the bump: re-pinning the new sha under the same version
    passes.

Hand-checks, A1–A5 on this machine:

The Zen checks (2, 7, 10, 11) need the real files on the box: the `force_installed` policy at
`/etc/zen/policies/policies.json` and the XPI at the fixed `install_url`. `omarchy dev link`
does not cover `/etc` or the fixed `default/**` install path, so build and install the package
from the worktree with `omarchy dev pkg-test omarchy-settings <worktree>` (needs the
`omarchy-pkgs` PKGBUILD checkout). That exercises the glob pickup and ownership -- assert with
`pacman -Qo /etc/zen/policies/policies.json`. But `pkg-test` installs with `--overwrite='*'`,
so pre-clean any residue at that path first, or it silently adopts the residue and the check
proves nothing. The unowned-file refusal (Decision 8) shows only on the real
`omarchy-update-system-pkgs` path, not under `pkg-test`; to see it, hand-place the two files
with `sudo install -D` (leaving both unowned) and run the real update. After the checks,
reinstall the release `omarchy-settings` to undo the `-dev` package.

1. Pre-clean, so Phase 0 residue does not mask the shipped mechanism. Remove any
   `x-scheme-handler/msteams` pin from `~/.config/mimeapps.list` and any leftover `/etc/zen`.
   A leftover unowned `/etc/zen/policies/policies.json` would block a real `omarchy-settings`
   upgrade (though not `pkg-test`'s `--overwrite`), so clearing it is required, not cosmetic. Confirm
   `xdg-mime query default x-scheme-handler/msteams` is empty. Run the migration and confirm
   the scheme resolves through `mimeinfo.cache` alone.
2. Confirm the content script injects on the launcher page from the real `force_installed`
   `/etc/zen` policy on a fresh Zen profile (the Phase 1 Step 0 check; Phase 0 tested only a
   temporary add-on).
3. With `teams-for-linux` present, then removed: the no-`teams-for-linux` web-app fallback
   and the loop guard (A3). Watch for a second window on the same-origin `/v2/` drift and on
   a cross-origin `teams.microsoft.com`->`teams.cloud.microsoft` hop, which only the handler
   throttle catches.
4. A meeting link opened from outside the browser (`xdg-open`, a mail client, a terminal),
   where the page carries no user gesture. If Chromium's external-protocol gate blocks it
   there, that is an accepted limitation of the click-driven design, not a ship blocker.
   Record the result.
5. The Zen-default case with no Chromium running, so a fresh Chromium process must read the
   flags and load the extension.
6. Confirm the residual: a signed-in web session lands on the meeting join screen, not Teams
   home.
7. Confirm the force-install works with `Status: default` on a fresh Zen profile. A profile
   with a user-set `xpinstall.signatures.required=true` in `prefs.js` would still block it.
8. Confirm the standalone guard: `matchMedia('(display-mode: standalone)').matches` is true
   in the Chromium `--app` web-app window and false in a normal tab, in both browsers. This
   is what keeps the web-app window from firing on any hop. If it does not hold on an engine,
   the marker + throttle remain the guard there. It is defense alongside the marker, never a
   replacement: dropping `omarchyWebapp` would contradict A5.1, A8, and Decision 3.
9. Check the leftover calendar tab after a click: its URL and UI stay on the launcher page,
   not the web join screen (A1).
10. Record what Zen's external-scheme prompt shows, to settle Gecko's grant keying
    (Constraints).
11. Confirm the Firefox `Preferences` block newly applied to Zen is benign (Design 4).

Rollback, if the feature is later pulled: a migration removes the flags entry and the
`.desktop`; the `omarchy-settings` package stops shipping `/etc/zen/policies/policies.json`,
so pacman removes it on upgrade.

### Phase 4. Every meeting format, every cloud (tests first)

Extends the shipped Phases 1-3 to the `## Extension` contract (Requirements 7-12, A9-A15,
Decisions 9-12). Minimal diff on the committed base. The settled design does not change: same
content script, same handler, same `.desktop`, same policy file, same migration. Only the
matcher, the host set, the emitted host, and the query filter change.

Files:

- `default/chromium/extensions/teams-join/content.js`
- `default/chromium/extensions/teams-join/manifest.json` (host set, version bump)
- `bin/omarchy-webapp-handler-teams`
- `default/firefox/teams-join.xpi` (rebuilt)
- `test/shell.d/chromium-teams-join-test.sh`
- `test/shell.d/webapp-handler-teams-test.sh`
- No change: `etc/zen/policies/policies.json`, `config/chromium-flags.conf`,
  `migrations/1788809981.sh`, `test/shell.d/teams-join-migration-test.sh`,
  `test/shell.d/firefox-teams-join-test.sh` (its byte pin and version-bump check do the work
  unchanged).

#### Step 0. Checks before any test code

Two checks. Each pins a fixture or closes a fork. Record the results under this heading, as
Phase 1 did. (The widened-host-set silent-reinstall check moves to the hand-checks below: it
needs the real rebuilt XPI, not a pre-TDD edit of the tree, and a prompt is a one-time cost,
not a design fork.)

1. **Live channel-meeting link shape.** The research pinned `/l/meetup-join/<thread>/0?context=`
   and did not cover channel meetings. Open a channel meeting from Teams (the UAA tenant is
   enough) and capture the link the browser lands on. Record: the thread suffix (`@thread.tacv2`
   or `@thread.skype`), the segment after the thread id (a message id, not `0`), and the query
   keys. Confirm the settled classic regex `l/meetup-join/19(:|%3[aA])[^#\s]+` matches it as-is.
   Use the captured shape, id redacted, as the channel-meeting fixture in both test files. If the
   live shape does not start with `19:` or `19%3a`, that is a spec change; stop and surface it. If
   no channel meeting can be captured on the day, fall back to the documented form
   `19:<id>@thread.tacv2/<messageId>?context=` (verified to match both the content and handler
   regexes) and mark the fixture unverified.

   **Step 0 check 1 result (2026-09-08, John-captured HAR on `teams.cloud.microsoft`): PASS.** A
   real channel meeting join link is
   `l/meetup-join/19:<id>@thread.tacv2/<messageId>?context=...` -- `@thread.tacv2`, a 13-digit
   message id (`1788865197722`) where the calendar form has `/0`. Both matchers accept it,
   verified: the content regex matches, and the handler classic branch extracts
   `host=teams.cloud.microsoft`, `path=l/meetup-join/19:<id>@thread.tacv2/<messageId>?context=`.
   This confirms the loosened Req 7 classic shape (no `/0`/`meeting_` requirement) catches channel
   meetings. Use this shape (id redacted) as the channel-meeting fixture. Bonus real NEGATIVE
   fixture from the same HAR: a channel MESSAGE link `l/message/19:<id>@thread.tacv2/<msgId>?...`
   with launcher `type=message` -- our shapes do not match it (not `meetup-join`/`meet`), so it
   does not fire (A12). Also confirms `teams.cloud.microsoft` is a live host in the set.
2. **Live `/meet/` launcher capture.** Open John's real `/meet/<id>?p=<passcode>` link and copy
   `location.href` at the launcher page (the Phase 0 method). Record the decoded `url=` value
   (expect `/_#/meet/<id>?p=...`), the `type` value, and every extra key the launcher adds. This
   pins the unknown-key fixture to real keys, and records whether `/meet/` commits as a page or
   302s to the launcher (both paths are covered either way).

**Step 0 check 2 result (2026-09-08, John-captured HAR, throwaway meeting): PASS.** The `/meet/`
link routed through `/dl/launcher/launcher.html` (a 200 document) as:
`?url=<encoded>&type=meet&deeplinkId=<guid>&directDl=true&msLaunch=true&enableMobilePage=true`,
with `url=` decoding to `/_#/meet/<id>?p=<pass>&anon=true`. So the launcher-added keys are `type`,
`deeplinkId`, `directDl`, `msLaunch`, `enableMobilePage` (top level) and `anon` INSIDE `url=`
(after `p=`); `fqdn`/`launchAgent` were absent in this capture (fqdn is ECS-flag-dependent per the
research). The A15 unknown-key fixture uses exactly this key set. Verified end to end with the
planned `content.js` logic: it reads `url=` on the launcher page, strips `/_#`, matches the short
shape, allow-lists to keep only `p=`, and emits `msteams://teams.microsoft.com/meet/<id>?p=<pass>`
-- `anon` dropped, `p=` kept, host preserved. This confirms the allow-list is load-bearing:
`anon=true` (an anonymous-join flag) rides inside `url=` and must be dropped.

#### `content.js`

Six changes. Comments update with the code.

1. **One anchored shape regex for both shapes.** Replace the `meetingPath` match (line 5) with a
   regex anchored at a path start and carrying both alternatives:

   ```
   /^\/(?:l\/meetup-join\/19(?::|%3[aA])[^#\s]+|meet\/[^\/?#\s]+(?:\?[^#\s]*)?)/
   ```

   Classic keeps its settled breadth: `[^#\s]+` after `19:`/`19%3a`, no `/0` and no `meeting_`
   requirement, so channel meetings (`@thread.tacv2`, `@thread.skype`, message id in place of
   `0`) keep matching. Short is `meet/<id>` with `<id>` = `[^\/?#\s]+` (not digits-only;
   `user@example.com` matches), then an optional `?query` taken only when it follows the id
   directly. A `/extra` tail stops the match at the id; the tail and anything after it are not
   carried. No live link carries a tail (research B), so this is tolerance, not a feature.
   `/meet/` cannot match inside `/l/meetup-join/` or `/convene/meetings` (no `/` after `meet`).

   The `^\/` anchor stops a meeting path buried inside another page's query from matching the
   `pathname+search` candidate: `/convene/meetings?url=/meet/123` does not START with the meeting
   shape, so it never matches (today's whole-`href` substring scan on line 25 would). Note: what
   makes "`url=` is read only on the launcher page" true is change 2's
   `pathname === "/dl/launcher/launcher.html"` gate plus the hash-only-on-`/v2/` rule, NOT this
   anchor -- do not drop the pathname gate.

2. **Candidate strings instead of a whole-`href` scan.** Replace lines 24-26 with: parse `href`
   once (`u = new URL(href)`), then

   - on the launcher page only (`u.pathname === "/dl/launcher/launcher.html"`):
     `v = u.searchParams.get("url") || ""` (one decode layer, as today), and try `meetingPath(v)`
     then `meetingPath(v.slice(v.indexOf("#") + 1))`. The second form handles the real launcher
     value `/_#/<path>`; the first handles a bare `/<path>`. No `type` gate (Requirement 9).
   - on every page, when nothing matched yet: `meetingPath(u.pathname + u.search)` (direct link,
     `p=`/`context=` in the page query). Then read the hash ONLY when `u.pathname` is `/v2/` (or
     the slash-less `/v2`, since `new URL` can drop the trailing slash) -- the A8 web-client
     fragment case: `meetingPath(u.hash.slice(1))`. Do NOT read the hash on
     other pages -- a `/convene/meetings?url=/_#/meet/123` URL lands `/meet/123` in
     `location.hash`, which would otherwise fire and violate A12/Decision 10 (grok round 2).

   Drop the `catch (e) { path = meetingPath(href) }` fallback (line 26): with the anchored regex a
   full `https://` string never matches, and `location.href` always parses. Keep the `try`.

3. **Allow-list the query.** Replace the `drop` regex (line 11) with a keep set. Same
   split-and-filter shape, inverted: keep a pair only when `x.split("=")[0]` is exactly `p` or
   `context`. Everything else goes, including `fqdn`, `type`, `directDl`, `msLaunch`,
   `enableMobilePage`, and any future launcher key (Requirement 11). Empty kept set: return the
   path with no `?`, as today.

4. **Emit the clicked host.** Line 27 becomes `"msteams://" + u.hostname + path`. `hostname`, not
   `host`, so a port can never leak into the scheme URL. No host is hard-coded anywhere in the
   script after this change (Requirement 10, Decision 11).

5. **Marker as a query key per layer (moved after `new URL`).** Move the marker check to AFTER
   `u = new URL(href)` (change 2) -- it now needs `u`, so it cannot stay at line 16 before `u`
   exists. Replace the bare `href.indexOf("omarchyWebapp")` with a helper that takes one
   already-decoded layer, isolates its query (the text after its first `?`), and returns true when
   the marker is a KEY there. Parse with the sandbox-available `URL`, NOT `URLSearchParams` (the
   Node test sandbox injects only `URL`; `new URLSearchParams(...)` throws in every case):
   `new URL("https://x/?" + query).searchParams.has("omarchyWebapp")`. Run it on three layers:
   `u.search`, `u.hash`, and the decoded `url=` value (`u.searchParams.get("url")`, read on every
   page; reading it for the marker can only stand down, which the Security tie-break prefers). A `/meet/` id or `p=` value containing the literal `omarchyWebapp` is path or value
   text, never a key, so it no longer stands the script down (Security delta, A15 collision case).
   The encoded launcher form `omarchyWebapp%3D1` still works: `searchParams.get("url")` decodes it
   to a real `omarchyWebapp=1` pair before the key check (the Phase 0 bug stays fixed).

6. **Latch key unchanged.** Line 32 stays: `"teamsjoin:" + path` with `%3a`/`%40` folded and the
   query cut at `?`. For `/meet/123?p=abc` that is `teamsjoin:/meet/123`; `p=` never reaches
   `sessionStorage` (Security). The standalone guard, `window.stop()`, and the fire-or-stand-down
   latch order stay as they are.

#### `manifest.json`

- `content_scripts[0].matches` and `host_permissions` become the same six entries, in this
  order: `https://teams.microsoft.com/*`, `https://teams.cloud.microsoft/*`,
  `https://teams.live.com/*`, `https://gov.teams.microsoft.us/*`,
  `https://dod.teams.microsoft.us/*`, `https://teams.microsoftonline.cn/*`. Exact `https://`
  hosts, no `<all_urls>`, no `http://`, no `tabs`, `webNavigation`, or background (Constraints
  delta). Bare `teams.microsoft.us` is not listed (Requirement 8).
- `version`: `0.1` to `0.2`. Zen reinstalls only on a version increase, so the bump is
  load-bearing (without it Zen keeps the old 3-host `0.1` XPI forever). On THIS branch the
  `firefox-teams-join-test.sh` version-bump check does NOT fire -- it early-exits on "no base
  manifest on `origin/quattro`" (the extension does not yet exist there; verified) -- so it does
  not gate the bump here. Add an explicit `.version == "0.2"` assertion to the manifest `jq`
  block in `chromium-teams-join-test.sh` (which does run) as the real gate. Post-merge, the
  firefox version-bump check enforces it against the base.
- The manifest test's `HOSTS` array must list the six in the same order: its `jq` comparison is
  order-sensitive.

#### `bin/omarchy-webapp-handler-teams`

Lines 5-9 change; nothing else. The classic and short shapes need different path reconstruction
(classic keeps its whole tail; short drops a `/extra` path segment but keeps the query and
fragment), so match them in SEPARATE `=~` branches rather than one combined shape. Host
alternation in a variable, used unquoted:

```
hosts='teams\.microsoft\.com|teams\.cloud\.microsoft|teams\.live\.com|gov\.teams\.microsoft\.us|dod\.teams\.microsoft\.us|teams\.microsoftonline\.cn'
```

Four branches (hosted + host-less, each classic + short); all verified in bash:

- **Hosted classic:** `^msteams:/*($hosts)/l/meetup-join/(19(:|%3[aA])[^[:space:]]+)$` ->
  `host=${BASH_REMATCH[1]}`, `path="l/meetup-join/${BASH_REMATCH[2]}"`. The `[^[:space:]]+` keeps
  the whole `/0?context=...#frag` tail, as today. `host` is the full host now (today builds
  `teams.${BASH_REMATCH[1]}`).
- **Hosted short:**
  `^msteams:/*($hosts)/meet/([^/?#[:space:]]+)(\?[^#[:space:]]*)?(#[^[:space:]]*)?(/[^[:space:]]*)?$`
  -> `host=${BASH_REMATCH[1]}`, `path="meet/${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"`.
  That is: id (group 2), an optional `?query` DIRECTLY after it (group 3, kept, slashes and all),
  an optional `#fragment` (group 4, kept), and a trailing `/extra` (group 5, DROPPED). This
  matches the content script exactly: `/meet/123?p=a/b` keeps `p=a/b`; `/meet/123?p=abc#/join`
  keeps the fragment; `/meet/123/extra?p=abc` yields `meet/123` (the `?p=` after `/extra` is not
  the id's query, so it is dropped -- the same result the content-script prefix match produces).
- **Host-less v1:** the same two regexes without the `($hosts)/` prefix, with
  `host="teams.microsoft.com"` (A5.1/A11: no cloud to preserve) and `path` built from the
  now-shifted group indices (classic: `l/meetup-join/${BASH_REMATCH[1]}`; short: id/query/frag are
  groups 1/2/3).
- The whitespace guard holds for both shapes (a space/tab/newline fails `$`, fallback goes home);
  a leading dash in a `/meet/` id is harmless (`web_url` starts `https://`, one quoted argv
  element). Bare `teams.microsoft.us` and `gov.teams.microsoft.us.evil.test` do not match the host
  alternation, so they go home (look-alike rule).
- Lines 10-14 (native branch) do not change. Every `msteams:` argument still goes to
  `teams-for-linux` unchanged, unlisted host included (Decision 4, Decision 11, A11). The host
  check stays fallback-only.
- Lines 15-35 do not change. `web_url="https://$host/$path"` already preserves the matched host.
  The throttle id (`${path%%\?*}`, `%%#*`, `%3a`/`%40` folds) already strips `p=`; for
  `/meet/123?p=abc#/x` the stamp holds `meet/123`. Marker-before-fragment logic is untouched.
- Update the Design 2 note that says the script "always rebuilds to `teams.microsoft.com`" and
  that the regex "guards external input, not anything the script emits". The script now emits the
  clicked host, so the fallback host list guards both.

#### `default/firefox/teams-join.xpi`

Rebuild after `content.js` and `manifest.json` are final, from
`default/chromium/extensions/teams-join`:
`python3 -m zipfile -c ../../../firefox/teams-join.xpi manifest.json content.js`. The existing
byte-pin test fails until this is done. The firefox version-bump check does NOT catch a forgotten
`0.2` on this branch (new-extension early exit); the `.version == "0.2"` assertion added to
`chromium-teams-join-test.sh` is what gates it here. No new firefox test.

#### `etc/zen/policies/policies.json`

No change. Confirmed from the file: the policy force-installs by `gecko.id` (`teams-join@omarchy`)
from the fixed `install_url`. Host permissions live in the manifest inside the XPI, so the wider
host set reaches Zen through the rebuilt XPI and the version bump alone. The hand-check (order of
work step 7) confirms the reinstall is silent.

#### Migration and flags

No change. The `--load-extension=` path and the `.desktop` are the same. Chromium re-reads the
extension directory on start; Zen reinstalls the XPI on the version bump. Users restart their
browser, as after any Omarchy update.

#### Spec text edits

Apply the "Edits to existing text this implies" list from the Extension section: Requirement 1,
A5.1, A8, the "three Teams hosts" wording in Constraints and Security, the "up to three" prompt
bound, the Design 1 and Design 2 rebuild notes, and Requirement 2's "no configuration" scope.
Remove the old `teams.live.com/meet/<id>` non-goal line. Update the Design 1 code block to the
final `content.js` and the Design 2 block to the final handler, so the doc stays the source the
tests were written against.

#### Test matrix

Test-first: write each case, watch it fail on the committed base, then implement. Existing cases
stay unless listed under "edits".

**`test/shell.d/chromium-teams-join-test.sh`** (manifest assertions plus the `run_node_test`
sandbox; the sandbox's `URL` already gives `hostname`):

Edits to existing cases:
- `HOSTS` becomes the six-entry set in manifest order. Pass message drops "three". Add a
  `.version == "0.2"` assertion to the same `jq`/manifest block -- this is the gate that actually
  enforces the version bump on this branch (the firefox version-bump check no-ops pre-merge; see
  the `manifest.json` note).
- `hosts` in the Node block becomes the six (five verified plus `.cn`), which exercises the emit
  on every listed host; `.cn` costs nothing here since the script has no host logic. The
  `HOSTS`/`jq` block, not this array, is what pins the manifest.
- `expectedColon`, `expectedEncoded`, `expectedWithContext` become per-host inside the loop:
  `msteams://${host}${path}`. `assertFires` description text changes to "rewrites to
  msteams://<page host>". Keep a `teams.microsoft.com` value available for the later NON-loop
  cases that still read them (`chromium-teams-join-test.sh:231` repeat-in-tab, `:247`
  two-meetings), which the edit list otherwise leaves as microsoft.com.
- `assertStandDownAndLatch` hop URL and `encodedMarkerHref` stay on `teams.microsoft.com`; they
  are guard tests, not host tests.

New cases (A-number in brackets):
- Per host in the loop [A9, A10, A15]: `/meet/123?p=abc` direct fires to
  `msteams://${host}/meet/123?p=abc`; `/meet/123` without `p=` fires with no query and no
  synthesized `p=`; launcher `url=/_#/meet/123?p=abc` with `type=meet`, `deeplinkId`,
  `launchAgent=join_launcher`, `fqdn=${host}`, and the Step 0 keys fires to
  `msteams://${host}/meet/123?p=abc`; launcher `url=/_#/l/meetup-join/...?context=...&fqdn=${host}`
  fires with `context=` only (the `/_#` prefix form is new; today's cases omit it);
  `/v2/?meetingjoin=true#/meet/123?p=abc` fires (a fragment that carries a meeting is a positive,
  per the updated Non-goals).
- Channel meeting, classic, on `teams.microsoft.com` and `gov.teams.microsoft.us` [A10, A15]: the
  Step 0 fixture (`@thread.tacv2`, message id in place of `0`, `%3a` form) fires and emits the
  path unchanged.
- DoD thread id [A10]:
  `https://dod.teams.microsoft.us/l/meetup-join/19:dod:meeting_abc@thread.v2/0?context=...` emits
  `msteams://dod.teams.microsoft.us/...`; assert the string does not contain `teams.microsoft.com`.
- Launcher on gov [A13, A15]: `launcherHref('gov.teams.microsoft.us', '/_#/meet/123?p=abc')` emits
  `msteams://gov.teams.microsoft.us/meet/123?p=abc`.
- Non-numeric id [A15]: `/meet/user@example.com?p=abc` fires; latch key is
  `teamsjoin:/meet/user@example.com`.
- Launcher without `type` [A13]: same `url=` payload, no `type` key, fires once; `store.size` is 1
  after the run.
- Launcher with a MISLEADING `type` on a valid meeting [A13, Requirement 9]:
  `url=/_#/meet/123?p=abc` with `type=chat` (a real meeting, wrong type) still FIRES -- this is
  the case that fails if someone adds a `type` gate, so it locks Requirement 9.
- Launcher with a non-meeting payload but a MEETING `type` [A13, Requirement 9]:
  `url=/_#/l/chat/0/0?users=a` with `type=meet` does NOT fire -- the embedded shape decides, so a
  meeting-looking `type` cannot force a non-meeting path (the complement of the case above;
  together they lock "shape decides, not type" both ways).
- Unknown keys dropped [A15, Req 11]: launcher
  `url=/_#/meet/123?p=abc&futureKey=1&msLaunch=true&directDl=true&enableMobilePage=true&suppressPrompt=true&type=meet`
  emits exactly `msteams://<host>/meet/123?p=abc`; classic variant with `context=` plus the same
  keys emits `context=` only. Order test: `futureKey=1&p=abc` still keeps `p=`.
- `p=` never in the latch key [A14, A15]: after firing `/meet/123?p=abc`, the store keys equal
  `['teamsjoin:/meet/123']`; a repeat of the same id with a different `p=` in the same store does
  not fire.
- Short-shape loop guards [A14]: `/meet/123` with a `matchMedia('(display-mode: standalone)')`
  stub returning true does NOT fire (standalone stand-down for the short shape, matching the
  classic case); and `/meet/user@example.com` then `/meet/user%40example.com` in one shared store
  map to the same latch key `teamsjoin:/meet/user@example.com` (the `%40`/`@` fold applies to
  `/meet/` ids too, A14), so the second stands down.
- Marker collision [A15, Security]: `https://teams.microsoft.com/meet/omarchyWebapp?p=omarchyWebapp`
  fires and emits that exact path and query; the launcher form of the same payload fires too. Then
  the real marker still stands down: `/meet/123?p=abc&omarchyWebapp=1` (page query), the launcher
  form with `omarchyWebapp%3D1` inside `url=`, and `/v2/?meetingjoin=true#/meet/123?omarchyWebapp=1`
  (fragment query) each stand down and latch.
- `/convene/` negative, THREE forms [A13, A15]:
  `https://<host>/convene/meetings?url=<searchParams-encoded /_#/meet/123?p=abc>` (hash stays in
  the query), the raw `?url=/meet/123?p=abc` (no `/_#`, kept in the query), AND -- the case that
  guards the fix -- the UNENCODED `?url=/_#/meet/123?p=abc` (the browser puts `#/meet/123?p=abc`
  in `location.hash`). All three do not fire and do not latch; the third is the one that fires if
  the hash is read off a non-`/v2/` page (so it locks change 2's pathname gate). Spread across
  `teams.microsoft.com` and `gov.teams.microsoft.us`.
- Launcher with a non-meeting payload [A13]:
  `launcherHref(host, '/_#/l/chat/0/0?users=a', { type: 'chat' })` and
  `/_#/l/channel/19:x@thread.tacv2/General` do not fire and do not latch.
- A12 negatives on one commercial and one gov host: `/v2/?meetingjoin=true#/light-meetings/launch`,
  `/light-meetings/launch?...`, `/l/meeting/new?subject=x`, and each of `/l/chat/`, `/l/call/`,
  `/l/channel/`, `/l/team/`, `/l/message/`, `/l/entity/`, `/l/app/`, `/l/task/`, `/l/file/`,
  `/l/meeting-share/` do not fire and do not latch. Add `https://teams.microsoft.com/meetup-join/19:x`
  (no `/l/`) and `/meet/` with an empty id as shape negatives.

**`test/shell.d/webapp-handler-teams-test.sh`**:

Edits to existing cases:
- Move `msteams://teams.microsoft.com/meet/abc123` out of `non_meetings`: it is a meeting now.
  Replace it with `msteams://teams.microsoft.us/meet/abc123` (bare host, not a web host) and
  `msteams://gov.teams.microsoft.us.evil.test/meet/abc123` (look-alike on a new host).
- The comment above the malformed-tail cases (lines 203-206) mentions only `meetup-join`; extend
  it to both shapes.

New cases, appended to `meeting_urls`/`meeting_https` so both the native-unchanged and the web-app
loops cover them [A9, A10, A11, A15] -- EXCEPT the final two bullets (whitespace/empty and
throttle), which do NOT go in those arrays; their placement is noted inline:
- `msteams://<host>/meet/123?p=abc` for each of the six hosts, expecting
  `https://<host>/meet/123?p=abc&omarchyWebapp=1` (host preserved; assert none of the gov/DoD/cn
  expectations contain `teams.microsoft.com`).
- `msteams://<host>/l/meetup-join/19:meeting_abc@thread.v2/0?context=...` for
  `gov.teams.microsoft.us` and `dod.teams.microsoft.us`, plus the DoD `19:dod:meeting_abc@thread.v2`
  id.
- Channel meeting classic on `teams.microsoft.com` (Step 0 fixture), `%3a` form.
- `msteams://teams.microsoft.com/meet/123` (no `p=`): fallback URL is `.../meet/123?omarchyWebapp=1`,
  nothing synthesized.
- `msteams://teams.microsoft.com/meet/user@example.com?p=abc` (non-numeric id).
- Host-less v1: `msteams:/meet/123?p=abc` and `msteams:///meet/123?p=abc` open on
  `teams.microsoft.com`.
- Fragment placement: `msteams://gov.teams.microsoft.us/meet/123?p=abc#/join` opens
  `https://gov.teams.microsoft.us/meet/123?p=abc&omarchyWebapp=1#/join`;
  `msteams://teams.live.com/meet/123#/join` opens `...?omarchyWebapp=1#/join`.
- Slash in the passcode [A9, A11]: `msteams://teams.microsoft.com/meet/123?p=a/b` opens
  `https://teams.microsoft.com/meet/123?p=a/b&omarchyWebapp=1` -- the `/` in the passcode is
  kept, not truncated (the short-form query stops only at `#`/whitespace, like the content
  matcher). The content-script side asserts the same emit.
- Tail dropped [A9, Req 7]: `msteams://teams.microsoft.com/meet/123/extra?p=abc` FIRES but the
  fallback opens `https://teams.microsoft.com/meet/123?omarchyWebapp=1` -- the `/extra` tail (and
  the `?p=` sitting after it) are dropped, matching the content script, NOT kept. A clean
  `msteams://teams.microsoft.com/meet/123?p=abc` keeps `p=`
  (`https://teams.microsoft.com/meet/123?p=abc&omarchyWebapp=1`). The corresponding content-script
  case asserts `/meet/123/extra?p=abc` emits `msteams://teams.microsoft.com/meet/123` (same drop).
- Whitespace in a `/meet/` id (space, tab, newline) and `msteams://teams.microsoft.com/meet/`
  (empty id) go HOME -- add these to the existing malformed-tail block
  (`webapp-handler-teams-test.sh:203-225`), asserting the web-app home page, NOT to
  `meeting_https` (which would wrongly assert a meeting window).
- Throttle [A14, Security], each in its OWN `begin_case web` block (near `:247`), not
  `meeting_*` array slots: `/meet/123?p=abc` twice in-window opens once; after the first open the
  stamp file's first field equals `meet/123` exactly (no `p=`); the same id with `p=other` inside
  the window is throttled; `msteams://teams.cloud.microsoft/meet/123?p=abc` after
  `msteams://teams.microsoft.com/meet/123?p=abc` is throttled (host-independent key, the
  cross-origin backstop); a classic id and a `/meet/` id in sequence both open (different keys,
  A14).

**`test/shell.d/firefox-teams-join-test.sh`**: no new cases. The byte pin fails until the XPI is
rebuilt (run it to see it fail, then pass). Its version-bump check no-ops on this branch (the
extension is not on `origin/quattro` yet), so the version bump is gated by the `.version` check
added to `chromium-teams-join-test.sh`, not here.

**`test/shell.d/teams-join-migration-test.sh`**: no change; run it to confirm nothing regressed.

#### Order of work

1. Step 0 checks; record results and fixtures here.
2. Handler tests, then handler. `bash test/shell.d/webapp-handler-teams-test.sh` green (the test
   files are mode 644; run them with `bash`, not `./`).
3. Content-script and manifest tests, then `content.js` and `manifest.json`.
   `bash test/shell.d/chromium-teams-join-test.sh` green.
4. Rebuild the XPI. `bash test/shell.d/firefox-teams-join-test.sh` green.
5. `./test/all` green.
6. Spec text edits from the list above.
7. Hand-checks on this machine, both with and without `teams-for-linux`: John's real `/meet/` link
   opens the meeting in the client, then in a web-app window; a real classic link still works
   (regression); the leftover calendar tab stays on the launcher page (A1); no loop on the web-app
   path. Confirm `teams-for-linux` v2.20.0 accepts `msteams://teams.microsoft.com/meet/<id>?p=...`
   live (the research says `/meet/` support merged in PR #2250; this settles A9 on the native
   path). No gov or DoD tenant is available; those hosts rest on the unit tests and Decision 9.
   Also confirm the widened host set installs silently: with the rebuilt `0.2` XPI, the real
   `force_installed` policy reinstalls in Zen with no permissions prompt (`about:addons` lists
   the new hosts) and Chromium `--load-extension` loads with no prompt. A prompt is a documented
   one-time cost, not a fork (Constraints delta).

#### Decisions assumed

- Decision 11 is resolved: emit `msteams://<host>/<path>`, forward unchanged, fallback on the
  original host. This plan builds on it.
- Decisions 9, 10, and 12 are taken at their recommended defaults and are pending John's final
  confirmation: preserve the cloud (9); `/convene/` stays web and never fires (10);
  `teams.microsoftonline.cn` is in the host set, best-effort, no acceptance criterion (12). If 12
  flips to "out", the change is three one-line removals: the manifest entry, the handler `hosts`
  alternation, and the `.cn` entry in each test's host array. Nothing else depends on it.

#### Review log (extension plan gate)

| Gate | Stage | Round | Findings | Integrated |
|------|-------|-------|----------|------------|
| Phase 4 plan | grok-review | 1 | 4 (0 P1, 2 P2, 2 P3) | 4; core verified sound vs real code (regexes match both shapes + reject A12, line refs correct, Dec11/allow-list/launcher-only/throttle/policy hold). Step 0 check 3 (version+XPI edit) moved to hand-checks (broke test-first); webapp whitespace/empty -> malformed block + throttle -> own case block (not the meeting arrays); added misleading-type launcher positive (locks no-type-gate); expectedColon kept for the non-loop cases |
| Phase 4 plan | grok-review | 2 | 4 (0 P1, 2 P2, 2 P3) | 4; real content.js bugs: hash read on every page would fire on /convene/?url=/_#/meet/ (fix: read hash only on /v2/); marker helper used new URLSearchParams which the Node sandbox lacks (fix: new URL().searchParams); stale "Step 0 check 3" ref in policy subsection; marker check moved after u=new URL(href) (used u before defined) |
| Phase 4 plan | grok-review | 3 (cap) | 2 (0 P1, 1 P2, 1 P3) | 2; core verified sound again. Added the UNENCODED /convene/?url=/_#/meet/ test form -- the one that actually fires if hash is read off a non-/v2/ page, so it guards round-2's fix (the two listed forms didn't). Corrected change-1 rationale: the ^\/ anchor doesn't make "url= launcher-only" true; change 2's pathname gate does. Cap reached |
| Phase 4 plan | codex-review (Sol, gpt-5.6-sol) | 1 | 2 (0 P1, 2 P2) | 2; impl confirmed consistent with source+spec. Both test-gaps: added short-shape loop guards (standalone /meet/ stand-down + %40/@ fold for /meet/ ids in shared latch); added the complement misleading-type negative (non-meeting payload + type=meet does NOT fire) -- with grok's positive, locks "shape decides, not type" both ways |
| Phase 4 plan | codex-review (Sol) | 2 | 1 (0 P1, 1 P2) | 1; handler-vs-content-script inconsistency: handler `[^space]*` kept the /meet/ /extra tail while the content script drops it (Req 7 "tail ignored"). Fixed handler shape to `meet/<id>(\?query)?` + trailing `(/[^space]*)?` throwaway group; verified in bash (/meet/123?p= keeps p=, /meet/123/extra?p= -> meet/123, path=group 2); both tests now assert the drop |
| Phase 4 plan | codex-review (Sol) | 3 (cap) | 1 (0 P1, 1 P2) | 1; round-2's regex was too tight: `[^/#space]*` truncated a passcode at `/` (p=a/b) and no suffix allowed a #fragment (fragment tests would fall home, violating A9/A11). Rewrote the handler as two branches (classic keeps its tail; short = `meet/(id)(\?[^#space]*)?(#[^space]*)?(/[^space]*)?` -> path=id+query+frag, drop /extra). Verified in bash: p=a/b kept, #/join kept, /meet/123/extra?p= -> meet/123 (matches content script). Added slash-in-passcode test. Cap reached |
| Phase 4 plan | claude-review (fable-5, single) | 1 | 5 (1 major, 4 nit) | 5; MAJOR: the firefox version-bump check NO-OPS on this branch (extension not on origin/quattro -> new-extension early exit), so a forgotten 0.2 bump would ship green and Zen would keep the old 3-host 0.1 XPI. Added an explicit .version=="0.2" assertion to the chromium manifest test + corrected 3 false claims. Nits: order-of-work uses bash not ./ (files are 644); /v2 slash-less pathname guard; hosts-Node rationale; Step 0 channel-meeting fallback fixture. fable independently RAN 23 content-regex inputs + the 4 handler branches + the marker helper in the Node sandbox -- all sound; every Req 7-12 + A9-A15 has a code change and a test. Plan gate COMPLETE |
| Phase 4 diff (3ecf4209) | grok-review | 1 | 0 | Clean, no findings (sandbox enforced, repo integrity verified). Ran both suites + node/bash edge probes: real launcher fixture drops anon keeps p=; channel @thread.tacv2/@thread.skype fire; negatives (/l/message, /convene/?url=, /v2/ no-meeting, /l/<type>/) don't; look-alikes/port/userinfo go home; p= not in stamp/latch; marker as query key; tests would catch a wrong impl (digits-only, /0-required, type gate, drop-list, hardcoded host, substring marker, hash-everywhere) |

## Phase 0 results

Chromium and Zen, 2026-09-06/07. Full detail in the task memory; summary:

- The earlier `webNavigation` hook was rejected. It works when the extension is installed
  while the browser is running, but never delivers `onBeforeNavigate` to a `force_installed`
  (policy) extension on Zen, the ship path. `chrome.tabs.*` events on the same extension
  work. The internal `WebNavigation` module fires. Only the extension-facing `webNavigation`
  API is silent: its primed listener fails to reconnect at startup, with a "listener not
  re-registered" error. Temporary and post-startup installs work; the policy path does not.
  An MV2 persistent-background build force-installed at startup failed the same way, so the
  fault is the policy/startup install path, not the manifest version. Signing: this Zen
  build's effective `xpinstall.signatures.required` is true, so the policy must set it false
  (which the policy engine allows; see Constraints). Verified the XPI then installs.
- The content-script auto-fire hook was confirmed by John in both real browsers. Chromium ran
  it via `--load-extension`, the ship path. Zen ran it via a temporary add-on, not the
  `force_installed` policy ship path; that injection is checked in Phase 1 Step 0. The
  script injects on the Teams hosts, auto-fires the moment the launcher page loads (before
  Microsoft's forward), and Teams for Linux opens on the meeting: no click, one-time allow.
  A button-on-click also works but loses the ~1–2 s race before Microsoft drops the meeting
  id. Meeting extraction pulls the meetup-join path from the launcher `url=` param, the
  query, or the fragment. Stripping the fragment (an early bug) sent the app to chat.
- The web-app fallback (no `teams-for-linux`) was validated end to end on the real system.
  With `teams-for-linux` removed, our handler + `.desktop` routing `msteams:`, a real meeting
  click auto-fired, the handler opened a Chromium web-app window on the meeting, and the
  `omarchyWebapp` guard stood the window's copy of the extension down. No loop. The guard is
  load-bearing: a build matching the literal `omarchyWebapp=1` looped, because Microsoft
  URL-encodes it to `omarchyWebapp%3D1` in the launcher `url=` param. Matching the bare
  token fixes it (Decision 3).
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
| plan (Decision 8b) | fable-review (for Sol) | 1 (delta) | 6 (0 blocker, 6 should-fix) | 6; caught that both XPI and /etc ship from omarchy-settings, not omarchy -- authoring moved to etc/zen/policies/policies.json, backup= and blast-radius noted |
| plan (Decision 8b) | fable-review (for Sol) | 2 (delta, verify) | 3 (0 blocker, 1 should-fix, 2 nit) | 3; round-1 fixes all landed clean; noted pkg-test's --overwrite can't show the unowned-file refusal, dropped drift-prone counts. Clean |
| implementation diff (Phases 1-3) | grok-review | 1 | 0 | Clean, no findings (sandbox enforced, repo integrity verified). Re-confirmed byte-identity, manifest MV3, .desktop keys, migration idempotency, policy shape + vendor keys, XPI pin; ran all 4 tests |
| implementation diff (Phases 1-3) | fable-review (for Sol) | 1 | 4 (0 blocker, 1 should-fix, 3 nit) | 4; all test-coverage gaps (code hand-probed sound): migration single-line/append/missing/stale-desktop, per-meeting latch, clock-stepped-back throttle, version-bump file-list. Integrated; tests now 46/58/12/7 |
| implementation diff (Phases 1-3) | claude-review | 1 (full, 4-lens panel) | 9 nit (0 blocker, 0 should-fix) | Security=SECURE, Correctness=ship, Reliability=ship, Testing=sound. Integrated 2 high-value test nits (version-bump enforcement fixture; handler tail-guard whitespace cases); rest surfaced to John as non-actionable (spec-diagnosed tradeoffs / inherited convention). Tests now 50/58/12/10 = 130 |
