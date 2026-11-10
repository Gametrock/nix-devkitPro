import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
old = b"/opt/devkitpro"
new = os.fsencode(root)
metadata_suffixes = {".pc", ".cmake", ".la", ".sh", ".specs", ".rules"}

for path in root.rglob("*"):
    if path.is_symlink():
        target = os.readlink(path)
        if target == "/opt/devkitpro" or target.startswith("/opt/devkitpro/"):
            path.unlink()
            path.symlink_to(target.replace("/opt/devkitpro", str(root), 1))
        continue

    if not path.is_file() or "pacman" in path.relative_to(root).parts:
        continue

    # bin/ also contains Python/shell scripts; never substitute inside ELF files.
    if (
        path.suffix not in metadata_suffixes
        and not path.name.endswith(("_rules", "_tools"))
        and "bin" not in path.parts
    ):
        continue

    data = path.read_bytes()

    if b"\0" not in data:
        relocated = data.replace(old, new).replace(
            b"/usr/bin/env bash", os.fsencode(sys.argv[2])
        )
        if relocated != data:
            path.write_bytes(relocated)
