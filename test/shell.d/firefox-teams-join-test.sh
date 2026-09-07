#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3
require_command git

ROOT="$ROOT" TEST_GIT_UPSTREAM="${TEST_GIT_UPSTREAM:-origin/quattro}" python3 <<'PY'
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

root = Path(os.environ["ROOT"])
base = os.environ.get("TEST_GIT_UPSTREAM", "origin/quattro")

ext_dir = root / "default/chromium/extensions/teams-join"
manifest_path = ext_dir / "manifest.json"
zen_policy_path = root / "etc/zen/policies/policies.json"
firefox_policy_path = root / "default/firefox/policies.json"
xpi_path = root / "default/firefox/teams-join.xpi"

expected_install_url = "file:///usr/share/omarchy/default/firefox/teams-join.xpi"
expected_signing = {"Value": False, "Status": "default"}
expected_extra_keys = {"ExtensionSettings", "DisableAppUpdate", "DefaultSerialGuardSetting"}


def fail(description, detail=""):
  if detail:
    print(detail, file=sys.stderr)
  print(f"not ok - {description}", file=sys.stderr)
  sys.exit(1)


def ok(description):
  print(f"ok - {description}")


def git_show(treeish, relpath):
  result = subprocess.run(
    ["git", "-C", str(root), "show", f"{treeish}:{relpath}"],
    capture_output=True,
  )
  if result.returncode != 0:
    return None
  return result.stdout


if not zen_policy_path.is_file():
  fail("Zen policy exists", str(zen_policy_path))
if not xpi_path.is_file():
  fail("teams-join XPI exists", str(xpi_path))
if not firefox_policy_path.is_file():
  fail("Firefox policy exists", str(firefox_policy_path))
if not manifest_path.is_file():
  fail("teams-join manifest exists", str(manifest_path))

manifest = json.loads(manifest_path.read_text())
gecko_id = manifest["browser_specific_settings"]["gecko"]["id"]
zen = json.loads(zen_policy_path.read_text())
firefox = json.loads(firefox_policy_path.read_text())

zen_policies = zen.get("policies")
if not isinstance(zen_policies, dict):
  fail("Zen policy has a policies object")

settings = zen_policies.get("ExtensionSettings")
if not isinstance(settings, dict):
  fail("Zen policy has ExtensionSettings")

if set(settings) != {gecko_id}:
  fail(
    "ExtensionSettings key equals gecko.id",
    f"expected {{{gecko_id}}}, got {sorted(settings)}",
  )

entry = settings[gecko_id]
if not isinstance(entry, dict):
  fail("ExtensionSettings entry is an object", str(entry))

mode = entry.get("installation_mode")
if mode != "force_installed":
  fail(
    "installation_mode is exactly force_installed",
    f"got {mode!r} (reject normal_installed, missing, or hyphenated)",
  )
ok("ExtensionSettings key equals gecko.id with installation_mode force_installed")

install_url = entry.get("install_url")
if install_url != expected_install_url:
  fail(
    "install_url equals the shipped XPI path exactly",
    f"expected {expected_install_url}\nactual   {install_url!r}",
  )
ok("install_url equals file:///usr/share/omarchy/default/firefox/teams-join.xpi")

firefox_prefs = firefox.get("policies", {}).get("Preferences")
zen_prefs = zen_policies.get("Preferences")
if not isinstance(firefox_prefs, dict):
  fail("Firefox policy has Preferences")
if not isinstance(zen_prefs, dict):
  fail("Zen policy has Preferences")

for key, value in firefox_prefs.items():
  if key not in zen_prefs:
    fail("Zen Preferences is a superset of Firefox Preferences", f"missing {key}")
  if zen_prefs[key] != value:
    fail(
      "Zen Preferences copies Firefox Preferences verbatim",
      f"{key}: expected {value}, got {zen_prefs[key]}",
    )

extra = set(zen_prefs) - set(firefox_prefs)
if extra != {"xpinstall.signatures.required"}:
  fail(
    "Zen Preferences adds exactly xpinstall.signatures.required",
    f"extra keys: {sorted(extra)}",
  )
if zen_prefs["xpinstall.signatures.required"] != expected_signing:
  fail(
    "xpinstall.signatures.required is {Value: false, Status: default}",
    f"got {zen_prefs['xpinstall.signatures.required']}",
  )
ok("Zen Preferences is a superset of Firefox Preferences with signing default off")

top_keys = set(zen_policies)
if "Preferences" not in top_keys:
  fail("Zen policy has Preferences")
if top_keys - {"Preferences"} != expected_extra_keys:
  fail(
    "only extra top-level policies keys are ExtensionSettings, DisableAppUpdate, DefaultSerialGuardSetting",
    f"got {sorted(top_keys - {'Preferences'})}",
  )
ok("Zen policy top-level keys beyond Preferences are ExtensionSettings, DisableAppUpdate, DefaultSerialGuardSetting")

if "ExtensionSettings" in firefox.get("policies", {}):
  fail("Firefox policy has no ExtensionSettings")
ok("Firefox policy has no ExtensionSettings")

source_files = {p.name: p.read_bytes() for p in ext_dir.iterdir() if p.is_file()}
with zipfile.ZipFile(xpi_path) as zf:
  members = set(zf.namelist())
  if members != set(source_files):
    fail(
      "XPI member names equal source file names",
      f"expected {sorted(source_files)}, got {sorted(members)}",
    )
  for name, data in source_files.items():
    got = zf.read(name)
    if got != data:
      fail(f"XPI member {name} matches source bytes")
ok("XPI members match source file names and bytes")

if base == "none":
  ok("version bump check skipped")
  sys.exit(0)

base_rel = "default/chromium/extensions/teams-join/manifest.json"
content_rel = "default/chromium/extensions/teams-join/content.js"
base_manifest = git_show(base, base_rel)
if base_manifest is None:
  ok(f"new extension: no base manifest on {base}")
  sys.exit(0)

changed = False
for rel in (base_rel, content_rel):
  base_bytes = git_show(base, rel)
  current_bytes = (root / rel).read_bytes()
  if base_bytes != current_bytes:
    changed = True

base_version = json.loads(base_manifest.decode())["version"]
current_version = manifest["version"]
if changed and base_version == current_version:
  fail(
    "bump the version",
    f"teams-join source changed from {base} but manifest.version is still {current_version}",
  )
if changed:
  ok("teams-join version bumped")
else:
  ok("teams-join version matches base (source unchanged)")
PY
