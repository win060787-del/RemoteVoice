#!/bin/zsh
# Render documentation from real native views without modifying app preferences.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
sources=("$ROOT"/Sources/MiAo/*.swift)
sources=("${(@)sources:#*/main.swift}")
swiftc -swift-version 6 -parse-as-library "${sources[@]}" \
  "$ROOT/scripts/documentation/ScreenshotRenderer.swift" -o "$WORK/render"
VOICE_BRIDGE_DATA_DIR="$WORK/data" VOICE_BRIDGE_MODEL_DIR="$WORK/models" \
  "$WORK/render" "$ROOT/docs/screenshots"
