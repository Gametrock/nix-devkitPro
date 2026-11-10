"""Regression tests for the small, project-owned relocation/inventory helpers."""

from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

RELOCATE, INVENTORY, UPDATE = sys.argv[1:]
sys.argv = sys.argv[:1]


class SDKHelpers(unittest.TestCase):
    def test_relocation_keeps_binary_payloads_and_relative_links(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sdk"
            root.mkdir()

            metadata = root / "base_tools"
            metadata.write_text(
                "export SHELL := /usr/bin/env bash\nSDK=/opt/devkitpro\n"
            )

            pc = root / "example.pc"
            pc.write_text("prefix=/opt/devkitpro/portlibs/switch\n")
            binary = root / "example.rules"
            payload = b"\x7fELF\x00/opt/devkitpro"
            binary.write_bytes(payload)

            relative = root / "relative"
            relative.symlink_to("example.pc")

            absolute = root / "absolute"
            absolute.symlink_to("/opt/devkitpro/example.pc")

            subprocess.run(
                [sys.executable, RELOCATE, str(root), "/nix/store/test-bash/bin/bash"],
                check=True,
            )

            self.assertIn("/nix/store/test-bash/bin/bash", metadata.read_text())
            self.assertNotIn("/opt/devkitpro", metadata.read_text())

            self.assertEqual(pc.read_text(), f"prefix={root}/portlibs/switch\n")
            self.assertEqual(binary.read_bytes(), payload)
            self.assertEqual(relative.readlink(), Path("example.pc"))
            self.assertEqual(absolute.resolve(), pc)

    def test_inventory_detects_loss_and_target_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "sdk"
            root.mkdir()
            archive = root / "libexample.a"
            archive.write_bytes(b"!<arch>\noriginal archive")

            manifest = Path(tmp) / "inventory.json"
            command = [sys.executable, INVENTORY]
            subprocess.run(command + ["capture", str(root), str(manifest)], check=True)

            self.assertIn("sha256", json.loads(manifest.read_text())["libexample.a"])
            subprocess.run(command + ["verify", str(root), str(manifest)], check=True)

            archive.write_bytes(b"!<arch>\nchanged archive")
            result = subprocess.run(
                command + ["verify", str(root), str(manifest)], capture_output=True
            )
            self.assertNotEqual(result.returncode, 0)
            archive.unlink()
            result = subprocess.run(
                command + ["verify", str(root), str(manifest)], capture_output=True
            )
            self.assertNotEqual(result.returncode, 0)


class ImageUpdates(unittest.TestCase):
    def run_update(self, fail):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "nix/images").mkdir(parents=True)
            (root / "flake.nix").touch()

            for image in ["devkitarm", "devkitppc", "devkita64"]:
                (root / f"nix/images/{image}.json").write_text("original pin\n")

            binaries = root / "bin"
            binaries.mkdir()

            mock = """import base64, hashlib, json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "skopeo":
    if "inspect" in args:
        print(json.dumps({"Digest": "sha256:" + "a" * 64}))
    elif "copy" in args:
        if os.environ.get("MOCK_FAIL_IMAGE") and os.environ["MOCK_FAIL_IMAGE"] in args[-2]:
            sys.exit(1)
        archive = args[-1].split(":", 2)[1]
        pathlib.Path(archive).write_bytes(b"image fixture")
elif name == "nix":
    print("sha256-" + base64.b64encode(hashlib.sha256(pathlib.Path(args[-1]).read_bytes()).digest()).decode())
"""
            for name in ["skopeo", "nix", "nix-store"]:
                binary = binaries / name
                binary.write_text(f"#!{sys.executable}\n{mock}")
                binary.chmod(0o755)

            env = os.environ | {
                "PATH": f"{binaries}:{os.environ['PATH']}",
                "MOCK_FAIL_IMAGE": "devkitppc" if fail else "",
            }
            result = subprocess.run(
                ["bash", "-euo", "pipefail", UPDATE, "all"],
                cwd=root,
                env=env,
                capture_output=True,
            )

            if fail:
                self.assertNotEqual(result.returncode, 0)
                for pin in (root / "nix/images").iterdir():
                    self.assertEqual(pin.read_text(), "original pin\n")
            else:
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                for pin in (root / "nix/images").iterdir():
                    data = json.loads(pin.read_text())
                    self.assertEqual(data["imageName"], f"devkitpro/{pin.stem}")
                    self.assertEqual(data["imageDigest"], "sha256:" + "a" * 64)
                    self.assertTrue(data["hash"].startswith("sha256-"))

    def test_new_pins(self):
        self.run_update(fail=False)

    def test_failed_prefetch_does_not_replace_any_pins(self):
        self.run_update(fail=True)


unittest.main()
