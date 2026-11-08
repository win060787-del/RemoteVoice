#!/usr/bin/env python3
"""Export reviewable working sources without Git history, caches or user data."""
import hashlib
from pathlib import Path
import subprocess
import tarfile

root = Path(__file__).resolve().parent.parent
allowed_dirs = {"Sources", "Tests", "Resources", "scripts", "docs", ".github"}
allowed_files = {"Package.swift", "Package.resolved", "README.md", "README_EN.md", "LICENSE", "NOTICE",
                 "THIRD_PARTY_NOTICES.md", "VERSION", "Makefile", "CHANGELOG.md", "CITATION.cff",
                 ".gitignore", ".swift-format", "qwen-requirements.lock.txt", "CONTRIBUTING.md", "CONTRIBUTING_EN.md", "SECURITY.md", "SECURITY_EN.md",
                 "CODE_OF_CONDUCT.md", "CODE_OF_CONDUCT_EN.md", "SUPPORT.md"}
blocked = {"qwen-runtime.json", "preferences.json", "install-context.plist", ".DS_Store"}
files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root).decode().split("\0")
selected = []
for name in sorted(set(files)):
    path = Path(name)
    if not name or path.parts[0] not in allowed_dirs and name not in allowed_files:
        continue
    if any(part.startswith("._") or part == "__pycache__" for part in path.parts):
        continue
    if path.name in blocked or path.suffix in {".wav", ".bin", ".safetensors", ".db", ".sqlite", ".log", ".pyc"}:
        continue
    source = root / path
    if not source.is_file() or source.is_symlink():
        continue
    # Reject the known development-machine markers instead of silently rewriting sources.
    if source.suffix in {".swift", ".sh", ".py", ".md", ".json", ".plist"}:
        content = source.read_text(errors="replace")
        markers = ("/Users/" + "winwang/", "/Volumes/" + "AI 工作区/", "0D3E30CF-" + "B14C-5DC3-271C-67E6893E040D")
        if any(marker in content for marker in markers):
            raise SystemExit(f"Private development marker in {name}")
    selected.append(path)
output = root / "dist" / "remotevoice-source-preview.tar.gz"
output.parent.mkdir(exist_ok=True)
with tarfile.open(output, "w:gz") as archive:
    for path in selected:
        archive.add(root / path, arcname=str(Path("RemoteVoice") / path), recursive=False)
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(output.suffix + ".sha256").write_text(f"{digest}  {output.name}\n")
print(f"{output} ({len(selected)} files)")
