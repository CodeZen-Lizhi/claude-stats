import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "update-appcast.py"


class UpdateAppcastTests(unittest.TestCase):
    def test_writes_apple_silicon_hardware_requirement(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<ul><li>Apple Silicon only</li></ul>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.0",
                    "--build",
                    "80",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.0.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="abc" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("<sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>", xml)
            self.assertIn("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>", xml)

    def test_custom_hardware_requirement_is_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<p>custom</p>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.1",
                    "--build",
                    "81",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.1.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="abc" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--hardware-requirements",
                    "arm64",
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>",
                out.read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
