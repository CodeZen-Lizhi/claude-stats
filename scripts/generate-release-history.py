#!/usr/bin/env python3
"""Generate the in-app release history Swift source from git tags."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from release_notes_lib import SEMVER_TAG_RE, CommitNote, read_commits, run_git, semver_key, semver_tags, tag_exists


DEFAULT_OUTPUT = Path("ClaudeStats/Models/ReleaseHistory.generated.swift")
DEFAULT_OVERRIDE_DIR = Path("release-notes/history")
DEFAULT_START_TAG = "v1.4.0"
FALLBACK_CHANGE = "Stability and release pipeline improvements."
PRIORITY_TYPES = ["feat", "fix", "perf", "refactor", "docs"]
MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


@dataclass
class ReleaseGroup:
    tags: list[str]
    ref: str
    commit: str
    is_virtual: bool = False


@dataclass(frozen=True)
class HistoryOverride:
    headline: str | None
    changes: tuple[str, ...] | None


@dataclass(frozen=True)
class HistoryEntry:
    version: str
    date: str
    headline: str
    changes: tuple[str, ...]


def commit_for_ref(repo: Path, ref: str) -> str:
    return run_git(repo, ["rev-list", "-n", "1", ref]).strip()


def commit_date(repo: Path, ref: str) -> str:
    raw = run_git(repo, ["show", "-s", "--format=%cI", ref]).strip()
    dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    return f"{MONTHS[dt.month - 1]} {dt.day}, {dt.year}"


def tags_for_release(repo: Path, current_tag: str) -> tuple[list[str], set[str]]:
    if not SEMVER_TAG_RE.match(current_tag):
        raise ValueError(f"current tag must look like v1.2.3 (got: {current_tag})")

    current_key = semver_key(current_tag)
    tags = [tag for tag in semver_tags(repo) if semver_key(tag) <= current_key]
    virtual_tags: set[str] = set()
    if current_tag not in tags:
        tags.append(current_tag)
        virtual_tags.add(current_tag)
    return sorted(tags, key=semver_key), virtual_tags


def release_groups(repo: Path, current_tag: str) -> list[ReleaseGroup]:
    tags, virtual_tags = tags_for_release(repo, current_tag)
    groups: list[ReleaseGroup] = []

    for tag in tags:
        is_virtual = tag in virtual_tags and not tag_exists(repo, tag)
        ref = "HEAD" if is_virtual else tag
        commit = commit_for_ref(repo, ref)

        if groups and not is_virtual and not groups[-1].is_virtual and groups[-1].commit == commit:
            groups[-1].tags.append(tag)
            groups[-1].ref = ref
        else:
            groups.append(ReleaseGroup(tags=[tag], ref=ref, commit=commit, is_virtual=is_virtual))

    return groups


def visible_changes(notes: list[CommitNote]) -> list[str]:
    ordered_notes: list[CommitNote] = []
    for commit_type in PRIORITY_TYPES:
        ordered_notes.extend(note for note in notes if note.commit_type == commit_type)
    ordered_notes.extend(note for note in notes if note.commit_type not in PRIORITY_TYPES)

    items: list[str] = []
    seen: set[str] = set()
    for note in ordered_notes:
        for item in note.items:
            if item and item not in seen:
                items.append(item)
                seen.add(item)
    return items


def read_history_override(repo: Path, tags: list[str], override_dir: Path) -> HistoryOverride | None:
    base_dir = override_dir if override_dir.is_absolute() else repo / override_dir
    for tag in reversed(tags):
        path = base_dir / f"{tag}.json"
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError(f"{path} must contain a JSON object")

        headline = data.get("headline")
        if headline is not None and (not isinstance(headline, str) or not headline.strip()):
            raise ValueError(f"{path} headline must be a non-empty string")

        raw_changes = data.get("changes")
        changes: tuple[str, ...] | None = None
        if raw_changes is not None:
            if not isinstance(raw_changes, list) or not raw_changes:
                raise ValueError(f"{path} changes must be a non-empty array")
            if not all(isinstance(change, str) and change.strip() for change in raw_changes):
                raise ValueError(f"{path} changes must contain only non-empty strings")
            changes = tuple(change.strip() for change in raw_changes)

        return HistoryOverride(
            headline=headline.strip() if isinstance(headline, str) else None,
            changes=changes,
        )
    return None


def entry_for_group(repo: Path, groups: list[ReleaseGroup], index: int, override_dir: Path) -> HistoryEntry:
    group = groups[index]
    previous_ref = groups[index - 1].ref if index > 0 else None
    notes = read_commits(repo, group.ref, previous_ref)
    generated_changes = visible_changes(notes)
    override = read_history_override(repo, group.tags, override_dir)

    if override:
        headline = override.headline or (generated_changes[0] if generated_changes else FALLBACK_CHANGE)
        changes = list(override.changes or generated_changes[:5] or [FALLBACK_CHANGE])
    else:
        headline = generated_changes[0] if generated_changes else FALLBACK_CHANGE
        remaining = generated_changes[1:6]
        changes = remaining or generated_changes[:1] or [FALLBACK_CHANGE]

    return HistoryEntry(
        version=" / ".join(tag.removeprefix("v") for tag in group.tags),
        date=commit_date(repo, group.ref),
        headline=headline,
        changes=tuple(changes[:5]),
    )


def history_entries(repo: Path, current_tag: str, start_tag: str, override_dir: Path) -> list[HistoryEntry]:
    start_key = semver_key(start_tag)
    groups = release_groups(repo, current_tag)
    entries = [
        entry_for_group(repo, groups, index, override_dir)
        for index, group in enumerate(groups)
        if semver_key(group.tags[-1]) >= start_key
    ]
    return list(reversed(entries))


def swift_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def render_swift(entries: list[HistoryEntry]) -> str:
    lines = [
        "// Generated by scripts/generate-release-history.py. Do not edit by hand.",
        "",
        "extension ReleaseHistoryCatalog {",
        "    static let generatedEntries: [ReleaseHistoryEntry] = [",
    ]

    for entry in entries:
        lines.extend(
            [
                "        ReleaseHistoryEntry(",
                f"            version: {swift_string(entry.version)},",
                f"            date: {swift_string(entry.date)},",
                f"            headline: {swift_string(entry.headline)},",
                "            changes: [",
            ]
        )
        lines.extend(f"                {swift_string(change)}," for change in entry.changes)
        lines.extend(
            [
                "            ]",
                "        ),",
            ]
        )

    lines.extend(["    ]", "}", ""])
    return "\n".join(lines)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="current release tag, e.g. v1.5.0")
    parser.add_argument("--start-tag", default=DEFAULT_START_TAG)
    parser.add_argument("--output", default=DEFAULT_OUTPUT, type=Path)
    parser.add_argument("--repo", default=Path.cwd(), type=Path)
    parser.add_argument("--override-dir", default=DEFAULT_OVERRIDE_DIR, type=Path)
    args = parser.parse_args()

    repo = args.repo.resolve()
    entries = history_entries(repo, args.tag, args.start_tag, args.override_dir)
    if not entries:
        raise ValueError(f"no release history entries found from {args.start_tag} through {args.tag}")

    output = args.output if args.output.is_absolute() else repo / args.output
    write_text(output, render_swift(entries))
    print(f"generated {output}")
    print(f"entries: {', '.join(entry.version for entry in entries)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"error: git command failed with exit code {error.returncode}: {' '.join(error.cmd)}", file=sys.stderr)
        if error.output:
            print(error.output, file=sys.stderr)
        raise SystemExit(error.returncode)
    except (ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
