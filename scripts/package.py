#!/usr/bin/env python3
"""Package verified local binaries, source and license without private files."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parents[1]
version = (root / "VERSION").read_text().strip()
assert version == "0.1.0", "Review package metadata before changing the version"
files = [root / name for name in ("VERSION", "LICENSE", "README.md")]
for directory, suffix in (("src", "*"), ("configs", "*.cfg"), ("compiled", "*.amxx")):
    files.extend(p for p in (root / directory).rglob(suffix) if p.is_file())
assert len(list((root / "compiled").glob("*.amxx"))) == 2
output = root / "dist" / f"kgb-cs16-extras-{version}.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        data = path.read_bytes()
        if path.suffix == ".amxx":
            assert data[:4] == b"XXMA"
        info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (2026, 1, 1, 0, 0, 0))
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n")
print(f"{digest}  {output.name}")
