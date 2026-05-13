#!/usr/bin/env python3
"""Prepend a release <item> to the Sparkle appcast.

The appcast is a small RSS file hosted on GitHub Pages
(https://1pitaph.github.io/claude-stats/appcast.xml). The release workflow
fetches the current copy, runs this script to add the new version's <item>,
and republishes it to the gh-pages branch.

Usage:
  update-appcast.py \
      --version 1.2.0 --build 42 \
      --url https://github.com/1pitaph/claude-stats/releases/download/v1.2.0/ClaudeStats-1.2.0.zip \
      --enclosure-attrs 'sparkle:edSignature="..." length="12345"' \
      --release-notes-link https://github.com/1pitaph/claude-stats/releases/tag/v1.2.0 \
      --min-system-version 14.0 \
      --in appcast.xml --out appcast.xml

If --in does not exist (or is empty) a fresh appcast skeleton is created.
Re-running for a version that's already in the appcast is a no-op.
"""
import argparse
import email.utils
import os
import sys
import time

FEED_URL = "https://1pitaph.github.io/claude-stats/appcast.xml"

SKELETON = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Claude Stats</title>
    <link>{feed}</link>
    <description>Most recent updates to Claude Stats.</description>
    <language>en</language>
  </channel>
</rss>
""".format(feed=FEED_URL)

ITEM_TEMPLATE = """    <item>
      <title>Version {version}</title>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_sys}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{notes_link}</sparkle:releaseNotesLink>
      <pubDate>{pub_date}</pubDate>
      <enclosure url="{url}" {enclosure_attrs} type="application/octet-stream"/>
    </item>
"""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--enclosure-attrs", required=True,
                   help='the `sparkle:edSignature="..." length="..."` string from sign_update')
    p.add_argument("--release-notes-link", required=True)
    p.add_argument("--min-system-version", default="14.0")
    p.add_argument("--in", dest="infile", default="appcast.xml")
    p.add_argument("--out", dest="outfile", default="appcast.xml")
    args = p.parse_args()

    if os.path.exists(args.infile) and os.path.getsize(args.infile) > 0:
        with open(args.infile, encoding="utf-8") as fh:
            xml = fh.read()
    else:
        xml = SKELETON

    version_tag = "<sparkle:shortVersionString>{}</sparkle:shortVersionString>".format(args.version)
    if version_tag in xml:
        print("appcast already contains version {} — leaving it unchanged".format(args.version))
        with open(args.outfile, "w", encoding="utf-8") as fh:
            fh.write(xml)
        return 0

    item = ITEM_TEMPLATE.format(
        version=args.version,
        build=args.build,
        min_sys=args.min_system_version,
        notes_link=args.release_notes_link,
        pub_date=email.utils.formatdate(time.time(), localtime=False, usegmt=True),
        url=args.url,
        enclosure_attrs=args.enclosure_attrs.strip(),
    )

    if "<item>" in xml:
        xml = xml.replace("    <item>", item + "    <item>", 1)
    elif "</channel>" in xml:
        xml = xml.replace("  </channel>", item + "  </channel>", 1)
    else:
        print("error: malformed appcast — no <item> or </channel> found", file=sys.stderr)
        return 1

    with open(args.outfile, "w", encoding="utf-8") as fh:
        fh.write(xml)
    print("added Version {} (build {}) to {}".format(args.version, args.build, args.outfile))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
