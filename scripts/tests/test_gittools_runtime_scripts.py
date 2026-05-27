import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
PRUNE_SCRIPT = SCRIPTS / "gittools" / "prune-debug-symbols.sh"
VERIFY_SCRIPT = SCRIPTS / "verify-gittools-runtime.sh"


class GitToolsRuntimeScriptTests(unittest.TestCase):
    def make_minimal_runtime(self, root: Path) -> None:
        bin_dir = root / "bin"
        bin_dir.mkdir(parents=True)
        for name in ("github-linguist", "scc"):
            tool = bin_dir / name
            tool.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            tool.chmod(0o755)

    def test_prune_removes_build_only_runtime_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dsym = root / "native.dSYM"
            dsym.mkdir()
            (dsym / "payload").write_text("symbols", encoding="utf-8")

            object_file = root / "extension.o"
            object_file.write_text("object", encoding="utf-8")

            cmake_build = root / "vendor" / "libgit2" / "build"
            (cmake_build / "CMakeFiles").mkdir(parents=True)
            (cmake_build / "CMakeCache.txt").write_text("cache", encoding="utf-8")
            (cmake_build / "CMakeFiles" / "artifact").write_text("tmp", encoding="utf-8")

            gem_cache = root / "gems" / "ruby" / "3.4.0" / "cache"
            gem_cache.mkdir(parents=True)
            (gem_cache / "github-linguist.gem").write_text("gem", encoding="utf-8")

            rugged_vendor = root / "gems" / "ruby" / "3.4.0" / "gems" / "rugged-1.9.0" / "vendor"
            rugged_vendor.mkdir(parents=True)
            (rugged_vendor / "source.c").write_text("source", encoding="utf-8")

            ruby_headers = root / "runtime" / "ruby" / "include"
            ruby_headers.mkdir(parents=True)
            (ruby_headers / "ruby.h").write_text("header", encoding="utf-8")

            default_rbs = root / "runtime" / "ruby" / "lib" / "ruby" / "gems" / "3.4.0" / "gems" / "rbs-3.8.0"
            default_rbs.mkdir(parents=True)
            (default_rbs / "rbs.rb").write_text("rbs", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(PRUNE_SCRIPT), str(root)],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(dsym.exists())
            self.assertFalse(object_file.exists())
            self.assertFalse(cmake_build.exists())
            self.assertFalse(gem_cache.exists())
            self.assertFalse(rugged_vendor.exists())
            self.assertFalse(ruby_headers.exists())
            self.assertFalse(default_rbs.exists())

    def test_verify_rejects_object_files_before_functional_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_minimal_runtime(root)
            (root / "extension.o").write_text("object", encoding="utf-8")

            result = subprocess.run(
                ["bash", str(VERIFY_SCRIPT), str(root)],
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("contains object files", result.stderr)

    def test_verify_rejects_code_signing_xattrs_before_functional_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_minimal_runtime(root)
            payload = root / "payload.txt"
            payload.write_text("payload", encoding="utf-8")

            fake_xattr = root / "fake-xattr"
            fake_xattr.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    case "$1" in
                      *payload.txt) echo "com.apple.cs.CodeSignature" ;;
                    esac
                    """
                ),
                encoding="utf-8",
            )
            fake_xattr.chmod(0o755)

            env = os.environ.copy()
            env["GITTOOLS_VERIFY_XATTR_CMD"] = str(fake_xattr)
            result = subprocess.run(
                ["bash", str(VERIFY_SCRIPT), str(root)],
                text=True,
                capture_output=True,
                env=env,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("code-signing extended attributes", result.stderr)


if __name__ == "__main__":
    unittest.main()
