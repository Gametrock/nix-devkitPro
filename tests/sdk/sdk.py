"""Check the installed SDK, host executable loaders, and all portlibs metadata"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


sdk = Path(os.environ["DEVKITPRO"])
report = Path(sys.argv[1])
report.mkdir(parents=True, exist_ok=True)
manifest = sdk.parents[1] / "share/devkitpro/inventory.json"
subprocess.run(
    [sys.executable, sys.argv[2], "verify", str(sdk), str(manifest)],
    check=True,
)


host_executables = []
for path in sdk.rglob("*"):
    if (
        path.is_symlink()
        or not path.is_file()
        or "pacman" in path.relative_to(sdk).parts
    ):
        continue

    with path.open("rb") as stream:
        header = stream.read(20)

    if header[:4] != b"\x7fELF" or header[18:20] != b"\x3e\x00":
        continue

    result = subprocess.run(
        ["patchelf", "--print-interpreter", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        continue  # Shared objects have no PT_INTERP; autoPatchelf checked their dependencies.

    interpreter = result.stdout.strip()
    assert interpreter.startswith("/nix/store/"), (path, interpreter)
    subprocess.run(
        [interpreter, "--list", str(path)],
        check=True,
        capture_output=True,
    )
    host_executables.append(str(path.relative_to(sdk)))

assert host_executables, "No host executables checked"


# Scope each query to one ABI plus its shared ABI subtree
shared = {
    "gba": "armv4t",
    "nds": "armv4t",
    "gamecube": "ppc",
    "wii": "ppc",
    "wiiu": "ppc",
}
modules = {}
known_issues = json.loads(Path(sys.argv[3]).read_text())
observed_issues = {}

for directory in sorted((sdk / "portlibs").iterdir()):
    if not directory.is_dir():
        continue

    search = [directory / "lib/pkgconfig", directory / "share/pkgconfig"]
    if directory.name in shared:
        search.append(sdk / "portlibs" / shared[directory.name] / "lib/pkgconfig")

    env = os.environ | {
        "PKG_CONFIG_LIBDIR": ":".join(map(str, search)),
        "PKG_CONFIG_PATH": "",
    }
    for pc in sorted(directory.rglob("*.pc")):
        # Static flag resolution checks the entire Requires/Requires.private closure and relocation.
        key = f"{directory.name}/{pc.stem}"
        result = subprocess.run(
            [
                "pkgconf",
                "--static",
                "--cflags",
                "--libs",
                "--print-errors",
                pc.stem,
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            issue = known_issues.get(key)
            if not issue or issue["missingRequirement"] not in result.stderr:
                raise RuntimeError(
                    f"Unexpected pkg-config failure for {key}: {result.stderr}"
                )

            assert (
                sdk / "pacman/var/lib/pacman/local" / issue["package"]
            ).is_dir(), issue
            observed_issues[key] = result.stderr.strip()
            print(f"KNOWN UPSTREAM DEFECT: {key}: {issue['reason']}")
            continue

        assert (
            key not in known_issues
        ), f"Upstream fixed {key}; remove its obsolete exception"
        flags = result.stdout.strip()
        assert "/opt/devkitpro" not in flags.replace(str(sdk), "SDK"), (pc, flags)
        modules[f"{directory.name}/{pc.stem}"] = flags


packages = sorted(
    path.name
    for path in (sdk / "pacman/var/lib/pacman/local").iterdir()
    if path.is_dir()
)
assert packages, "Package provenance is missing"

compiler_directories = {
    "arm-none-eabi": "devkitARM",
    "powerpc-eabi": "devkitPPC",
    "aarch64-none-elf": "devkitA64",
}
for compiler, directory in compiler_directories.items():
    if not (sdk / directory).is_dir():
        continue

    subprocess.run([f"{compiler}-gcc", "--version"], check=True)
    subprocess.run([f"{compiler}-g++", "--version"], check=True)
    if shutil.which(f"{compiler}-gdb"):
        subprocess.run(
            [f"{compiler}-gdb", "--batch", "--nx", "-ex", "show version"],
            check=True,
        )


(report / "report.json").write_text(
    json.dumps(
        {
            "hostExecutables": host_executables,
            "portlibsModules": modules,
            "packages": packages,
            "knownUpstreamDefects": observed_issues,
        },
        indent=2,
    )
    + "\n"
)
print(
    f"Checked {len(host_executables)} host executables, "
    f"{len(modules)} portlibs modules, {len(packages)} packages"
)
