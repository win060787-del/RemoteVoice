#!/bin/zsh
# Keep the verified latest app; only recognized build artifacts in this directory are removed.
set -euo pipefail
[[ $# == 2 ]] || exit 2
artifact_dir="$1"
latest_name="$2"
[[ -d "$artifact_dir/$latest_name/Contents" ]] || { echo '未找到最新应用，拒绝清理旧构建。' >&2; exit 1; }
for candidate in "$artifact_dir"/*.app(N); do
  [[ "${candidate:t}" == "$latest_name" ]] || rm -rf "$candidate"
done
for candidate in "$artifact_dir"/remotevoice-*.tar.gz(N) "$artifact_dir"/remotevoice-*.tar.gz.sha256(N) "$artifact_dir"/remotevoice-*.zip(N) "$artifact_dir"/remotevoice-*.dmg(N); do
  rm -f "$candidate"
done
# Historical source-release output, when present.
for candidate in "$artifact_dir"/source/remotevoice-*.tar.gz(N) "$artifact_dir"/source/remotevoice-*.tar.gz.sha256(N); do
  rm -f "$candidate"
done
