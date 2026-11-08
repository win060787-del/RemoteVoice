#!/bin/zsh
# Copyright (c) 2026 FanXeon@Poemcoder with Codex
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/project.sh"
FINAL_BUILD_APP="$BUILD_APP"
cd "$ROOT"
swift build -c release

mkdir -p "$ROOT/dist"
STAGING_ROOT="$(mktemp -d "$ROOT/dist/.build-staging.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
BUILD_APP="$STAGING_ROOT/$APP_BUNDLE_NAME"
CONTENTS="$BUILD_APP/Contents"
RUNTIME_ROOT="$CONTENTS/Resources/Runtime"

mkdir -p \
  "$CONTENTS/MacOS" \
  "$CONTENTS/Resources" \
  "$RUNTIME_ROOT/Resources" \
  "$RUNTIME_ROOT/scripts/lib"
cp "$BUILD_BIN" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
# Remove compiler debug records containing the build machine's source paths.
xcrun strip -S "$CONTENTS/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/WhisperModel.sha256" "$CONTENTS/Resources/WhisperModel.sha256"
ditto "$ROOT/Resources/HardwareProfiles" "$CONTENTS/Resources/HardwareProfiles"
ditto "$ROOT/Resources/Brand" "$CONTENTS/Resources/Brand"
"$ROOT/scripts/build-icon.sh" "$CONTENTS/Resources/AppIcon.icns" >/dev/null

cp "$ROOT/Resources/Info.plist" "$RUNTIME_ROOT/Resources/Info.plist"
cp "$ROOT/Resources/WhisperModel.sha256" "$RUNTIME_ROOT/Resources/WhisperModel.sha256"
ditto "$ROOT/Resources/HardwareProfiles" "$RUNTIME_ROOT/Resources/HardwareProfiles"
cp "$ROOT/VERSION" "$RUNTIME_ROOT/VERSION"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$ROOT/NOTICE" "$CONTENTS/Resources/NOTICE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/scripts/qwen_worker.py" "$RUNTIME_ROOT/scripts/qwen_worker.py"
for script in \
  start.sh \
  stop.sh \
  run.sh \
  run-with-mapping.sh \
  check-buttons.sh \
  remote-mapping.sh \
  codex-accessibility.sh \
  configure-qwen.sh \
  repair-runtime.sh; do
  cp "$ROOT/scripts/$script" "$RUNTIME_ROOT/scripts/$script"
done
cp "$ROOT/scripts/lib/project.sh" "$RUNTIME_ROOT/scripts/lib/project.sh"
cp "$ROOT/scripts/lib/environment.sh" "$RUNTIME_ROOT/scripts/lib/environment.sh"
chmod 0755 "$RUNTIME_ROOT/scripts"/*.sh

BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PROJECT_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$BUILD_APP"
codesign --verify --deep --strict "$BUILD_APP"
if [[ -e "$FINAL_BUILD_APP" ]]; then
  mv "$FINAL_BUILD_APP" "$STAGING_ROOT/previous.app"
fi
if ! mv "$BUILD_APP" "$FINAL_BUILD_APP"; then
  [[ ! -e "$STAGING_ROOT/previous.app" ]] || mv "$STAGING_ROOT/previous.app" "$FINAL_BUILD_APP"
  exit 1
fi
"$ROOT/scripts/prune-builds.sh" "$ROOT/dist" "$APP_BUNDLE_NAME"
echo "$FINAL_BUILD_APP"
