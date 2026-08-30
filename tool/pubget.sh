#!/usr/bin/env bash
#
# Run "flutter pub get", then repair the one thing pub get reliably breaks on iOS.
#
# The Flutter tool regenerates
# ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift
# on every pub get, always with its own default minimum iOS version (13.0 as of
# Flutter 3.44). It only raises that to the Runner target's deployment target
# during "flutter build/run ios". Because file_picker_darwin requires iOS 14.0,
# a pub get followed by an Xcode-driven build fails package resolution with:
#
#   The package product 'file-picker-darwin' requires minimum platform version
#   14.0 for the iOS platform, but this target supports 13.0
#
# The Dev/Prod schemes carry a pre-action that repairs this, but Xcode resolves
# packages before pre-actions run, so that only helps from the second build on.
# Running pub get through this script keeps the manifest correct at all times.
#
# Usage: tool/pubget.sh [extra flutter pub get args]
# Override the flavor used for the config-only pass with IOS_SYNC_FLAVOR.

set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer FVM so the SDK pinned in .fvmrc is used, exactly as Xcode does via
# FLUTTER_ROOT in Flutter/Generated.xcconfig.
if [ -x .fvm/flutter_sdk/bin/flutter ]; then
  flutter=(.fvm/flutter_sdk/bin/flutter)
elif command -v fvm >/dev/null 2>&1; then
  flutter=(fvm flutter)
else
  flutter=(flutter)
fi

"${flutter[@]}" pub get "$@"

if [ "$(uname -s)" != "Darwin" ] || [ ! -d ios ]; then
  exit 0
fi

echo "Syncing iOS build configuration and Swift package manifest..."
"${flutter[@]}" build ios --config-only --no-codesign --flavor "${IOS_SYNC_FLAVOR:-Dev}"
