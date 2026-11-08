#!/bin/zsh
# Select an existing local runtime; never download dependencies or models implicitly.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/project.sh"
if [[ $# != 2 ]]; then
  echo '用法：configure-qwen.sh Python可执行文件 模型文件夹' >&2
  exit 2
fi
[[ "$(uname -m)" == arm64 ]] || { echo '千问 MLX 需要 Apple Silicon；Intel Mac 请使用 Whisper。' >&2; exit 1; }
[[ -x "$1" ]] || { echo '请选择有效的 Python 可执行文件。' >&2; exit 1; }
"$1" - "$2" "$APP_DATA_DIR" <<'PY'
import hashlib, json, os, sys, tempfile
from pathlib import Path
model = Path(sys.argv[1]).expanduser().resolve()
destination = Path(sys.argv[2]).expanduser().resolve()
for filename in ('config.json', 'model.safetensors'):
    if not (model / filename).is_file():
        raise SystemExit(f'模型文件缺失：{filename}')
# Check the selected environment before activating it.
import mlx_audio.stt
with (model / 'model.safetensors').open('rb') as source:
    digest = hashlib.file_digest(source, 'sha256').hexdigest()
destination.mkdir(parents=True, exist_ok=True, mode=0o700)
def portable(path):
    try: return str(path.relative_to(destination))
    except ValueError: return str(path)
# Keep a venv interpreter's invocation path; resolving its symlink loses venv packages.
python = Path(os.path.abspath(sys.executable))
config = dict(pythonPath=portable(python), modelPath=portable(model), modelSHA256=digest)
fd, temporary = tempfile.mkstemp(prefix='.qwen-', dir=destination)
try:
    with os.fdopen(fd, 'w') as target:
        json.dump(config, target, ensure_ascii=False, indent=2)
        target.write('\n')
    os.replace(temporary, destination / 'qwen-runtime.json')
finally:
    if os.path.exists(temporary): os.unlink(temporary)
print('千问模型配置已保存；模型内容已计算 SHA-256。')
PY
