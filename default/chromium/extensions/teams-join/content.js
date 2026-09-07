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
