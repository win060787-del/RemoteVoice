#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
mkdir -p "$TEMP_ROOT/遥声.app/Contents" "$TEMP_ROOT/old.app/Contents"
: > "$TEMP_ROOT/remotevoice-source-preview.tar.gz"
: > "$TEMP_ROOT/notes.txt"
"$ROOT/scripts/prune-builds.sh" "$TEMP_ROOT" "遥声.app"
[[ -d "$TEMP_ROOT/遥声.app/Contents" ]]
[[ ! -e "$TEMP_ROOT/old.app" ]]
[[ ! -e "$TEMP_ROOT/remotevoice-source-preview.tar.gz" ]]
[[ -f "$TEMP_ROOT/notes.txt" ]]
if "$ROOT/scripts/prune-builds.sh" "$TEMP_ROOT" "missing.app" 2>/dev/null; then exit 1; fi
[[ -f "$TEMP_ROOT/notes.txt" ]]
# A compiler failure must leave both the latest usable app and old artifacts untouched.
project="$TEMP_ROOT/project"
mkdir -p "$project/scripts/lib" "$project/Resources" "$project/dist/遥声.app/Contents" "$TEMP_ROOT/bin"
cp "$ROOT/scripts/build-app.sh" "$project/scripts/"
cp "$ROOT/scripts/lib/project.sh" "$project/scripts/lib/"
cp "$ROOT/Resources/Info.plist" "$ROOT/Resources/WhisperModel.sha256" "$project/Resources/"
cp "$ROOT/VERSION" "$project/"
print -r -- 'last usable build' > "$project/dist/遥声.app/Contents/marker"
print -r -- 'old preview' > "$project/dist/remotevoice-old.tar.gz"
print -r -- '#!/bin/zsh
exit 17' > "$TEMP_ROOT/bin/swift"
chmod +x "$TEMP_ROOT/bin/swift"
if PATH="$TEMP_ROOT/bin:$PATH" zsh "$project/scripts/build-app.sh" >/dev/null 2>&1; then exit 1; fi
[[ "$(<"$project/dist/遥声.app/Contents/marker")" == 'last usable build' ]]
[[ -f "$project/dist/remotevoice-old.tar.gz" ]]
echo 'Build retention tests: OK' 
