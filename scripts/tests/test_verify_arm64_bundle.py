import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-arm64-bundle.sh"


class VerifyArm64BundleTests(unittest.TestCase):
    def run_verifier(self, root: Path, lipo_output: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp:
            tools = Path(temp)
            file_cmd = tools / "fake-file"
            lipo_cmd = tools / "fake-lipo"
            file_cmd.write_text("#!/usr/bin/env bash\necho \"$1: Mach-O 64-bit executable\"\n", encoding="utf-8")
            lipo_cmd.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    echo "{lipo_output}"
                    """
                ),
                encoding="utf-8",
            )
            file_cmd.chmod(0o755)
            lipo_cmd.chmod(0o755)
            env = os.environ.copy()
            env["ARCH_VERIFY_FILE_CMD"] = str(file_cmd)
            env["ARCH_VERIFY_LIPO_CMD"] = str(lipo_cmd)
            return subprocess.run(
                ["bash", str(SCRIPT), str(root)],
                text=True,
                capture_output=True,
                env=env,
            )

    def test_accepts_arm64_only_macho_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "AppBinary").write_text("fixture", encoding="utf-8")

            result = self.run_verifier(root, "arm64")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("arm64-only", result.stdout)

    def test_rejects_universal_macho_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "AppBinary").write_text("fixture", encoding="utf-8")

            result = self.run_verifier(root, "x86_64 arm64")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected arm64", result.stderr)


if __name__ == "__main__":
    unittest.main()
