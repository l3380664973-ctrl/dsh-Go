#!/usr/bin/env bash
# Patches iOS plugin sources the Xcode on the machine cannot compile.
#
# Why this exists: `connectivity_plus` 7.3.2 calls `NWPath.isUltraConstrained`,
# an API that only exists in the iOS SDK shipped with newer Xcode. On Xcode
# 16.4 (iOS 18.5 SDK) the build stops with:
#
#   Swift Compiler Error (Xcode): Value of type 'NWPath' has no member 'isUltraConstrained'
#   .../connectivity_plus/PathMonitorConnectivityProvider.swift:28:39
#
# The property only refines what "constrained" means for connectivity
# reporting, which this app does not act on, so answering `false` is a safe
# stand-in until the plugin or the toolchain moves on. The patch is idempotent
# and prints what it touched; nothing else in the tree changes.
#
# Usage: tooling/ios-ci-plugin-patches.sh   (CI runs it before `flutter build ios`;
#        run it by hand on a Mac with the same error)
set -euo pipefail

PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
patched=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  if grep -q 'isUltraConstrained' "$file"; then
    # `path.isUltraConstrained` -> `false`
    perl -0pi -e 's/\b(?:path\.)?isUltraConstrained\b/false/g' "$file"
    echo "patched: ${file#"$PUB_CACHE"/}"
    patched=$((patched + 1))
  fi
done < <(find "$PUB_CACHE/hosted" -type f -name 'PathMonitorConnectivityProvider.swift' 2>/dev/null || true)

if [ "$patched" -eq 0 ]; then
  echo "no connectivity_plus sources needed patching"
fi
