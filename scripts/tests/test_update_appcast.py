import json
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

    def test_writes_delta_enclosures_when_present(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            out = root / "appcast.xml"
            notes.write_text("<p>delta release</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "78",
                            "deltaFromDisplay": "1.8.0",
                            "url": "https://example.com/ClaudeStats-82-from-78.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta-a" length="456"',
                        },
                        {
                            "deltaFrom": "79",
                            "url": "https://example.com/ClaudeStats-82-from-79.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta-b" length="789"',
                        },
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.2",
                    "--build",
                    "82",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.2.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("<sparkle:deltas>", xml)
            self.assertIn('sparkle:deltaFrom="78"', xml)
            self.assertIn('sparkle:deltaFrom="79"', xml)
            self.assertIn('sparkle:edSignature="delta-a" length="456"', xml)
            self.assertIn('sparkle:edSignature="delta-b" length="789"', xml)
            self.assertIn(
                '<enclosure url="https://example.com/ClaudeStats-1.8.2.zip" sparkle:edSignature="full" length="123" type="application/octet-stream"/>',
                xml,
            )
            self.assertIn("下载大小", xml)
            self.assertIn("增量更新包", xml)
            self.assertIn("从 1.8.0 (build 78) 更新", xml)
            self.assertIn("从 build 79 更新", xml)
            self.assertIn("完整安装包", xml)
            self.assertIn("较旧版本会自动回退下载", xml)
            self.assertIn("更新内容", xml)
            self.assertLess(xml.index("下载大小"), xml.index("<p>delta release</p>"))

    def test_formats_download_sizes_in_release_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            out = root / "appcast.xml"
            notes.write_text("<p>larger release</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "84",
                            "deltaFromDisplay": "1.8.4",
                            "url": "https://example.com/ClaudeStats-85-from-84.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta" length="2156350"',
                        }
                    ]
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.5",
                    "--build",
                    "85",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.5.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="101037424"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            xml = out.read_text(encoding="utf-8")
            self.assertIn("从 1.8.4 (build 84) 更新", xml)
            self.assertIn("2.2 MB", xml)
            self.assertIn("101 MB", xml)
            self.assertLess(xml.index("下载大小"), xml.index("<p>larger release</p>"))

    def test_omits_delta_container_without_delta_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            out = root / "appcast.xml"
            notes.write_text("<p>full only</p>", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.3",
                    "--build",
                    "83",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.3.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--out",
                    str(out),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("<sparkle:deltas>", out.read_text(encoding="utf-8"))

    def test_existing_version_is_left_unchanged_even_with_deltas(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            notes = root / "notes.html"
            deltas = root / "deltas.json"
            appcast = root / "appcast.xml"
            notes.write_text("<p>new</p>", encoding="utf-8")
            deltas.write_text(
                json.dumps(
                    [
                        {
                            "deltaFrom": "80",
                            "url": "https://example.com/ClaudeStats-84-from-80.delta",
                            "enclosureAttrs": 'sparkle:edSignature="delta" length="456"',
                        }
                    ]
                ),
                encoding="utf-8",
            )
            original = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:shortVersionString>1.8.4</sparkle:shortVersionString>
      <enclosure url="https://example.com/original.zip" sparkle:edSignature="original" length="1" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
            appcast.write_text(original, encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--version",
                    "1.8.4",
                    "--build",
                    "84",
                    "--url",
                    "https://example.com/ClaudeStats-1.8.4.zip",
                    "--enclosure-attrs",
                    'sparkle:edSignature="full" length="123"',
                    "--release-notes-file",
                    str(notes),
                    "--deltas-file",
                    str(deltas),
                    "--in",
                    str(appcast),
                    "--out",
                    str(appcast),
                ],
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(appcast.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
