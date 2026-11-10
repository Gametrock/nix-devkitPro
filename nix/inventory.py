import hashlib
import json
from pathlib import Path
import sys


def inventory(root):
    entries = {}
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))

        if path.is_symlink():
            entries[relative] = {"type": "symlink"}
        elif path.is_dir():
            entries[relative] = {"type": "directory"}
        elif path.is_file():
            record = {"type": "file"}
            with path.open("rb") as stream:
                header = stream.read(20)
                foreign_elf = (
                    header[:4] == b"\x7fELF"
                    and int.from_bytes(
                        header[18:20], "little" if header[5] == 1 else "big"
                    )
                    != 62
                )
                if header.startswith(b"!<arch>\n") or foreign_elf:
                    stream.seek(0)
                    record["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()

            entries[relative] = record
        else:
            raise RuntimeError(f"Unexpected SDK file type: {path}")
    return entries


def main():
    mode, directory, manifest = sys.argv[1:]
    root = Path(directory)
    current = inventory(root)

    if mode == "capture":
        Path(manifest).write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
    elif mode == "verify":
        original = json.loads(Path(manifest).read_text())
        if current != original:
            changed = sorted(
                key
                for key in current.keys() | original.keys()
                if current.get(key) != original.get(key)
            )
            raise RuntimeError(
                f"SDK membership or target binaries changed: {changed[:30]}"
            )

        protected = sum("sha256" in record for record in current.values())
        print(
            f"Verified {len(current)} entries; {protected} target ELF/archive hashes unchanged"
        )
    else:
        raise ValueError(f"Unknown inventory mode: {mode}")


if __name__ == "__main__":
    main()
