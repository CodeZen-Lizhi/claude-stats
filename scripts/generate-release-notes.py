#!/usr/bin/env python3
"""Generate GitHub and Sparkle release notes from source commits."""

from __future__ import annotations

import argparse
import html
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


RELEASE_REPO_URL = "https://github.com/1pitaph/claude-stats-releases"
SEMVER_TAG_RE = re.compile(r"^v\d+\.\d+\.\d+$")
CONVENTIONAL_RE = re.compile(r"^(?P<type>[A-Za-z]+)(?:\([^)]+\))?!?:\s*(?P<summary>.+)$")
RELEASE_BUMP_RE = re.compile(r"^chore\(release\)!?:\s*v\d+\.\d+\.\d+(?:\s+\[skip ci\])?$", re.IGNORECASE)
LIST_ITEM_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)、])\s+(?P<text>.+)$")
HEADING_ONLY_RE = re.compile(r"^(?:详细变更|变更|changes?)\s*[:：]$", re.IGNORECASE)
TRAILER_RE = re.compile(r"^(?:Signed-off-by|Co-authored-by|Reviewed-by):\s", re.IGNORECASE)

GROUP_ORDER = ["新功能", "修复", "性能", "改进", "工程与发布", "其他"]
SPARKLE_PRIMARY_GROUPS = ["新功能", "修复", "性能", "改进"]
SPARKLE_FALLBACK_GROUPS = ["工程与发布", "其他"]
TYPE_TO_GROUP = {
    "feat": "新功能",
    "fix": "修复",
    "perf": "性能",
    "refactor": "改进",
    "docs": "改进",
    "style": "改进",
    "build": "工程与发布",
    "ci": "工程与发布",
    "chore": "工程与发布",
    "test": "工程与发布",
}


@dataclass(frozen=True)
class CommitNote:
    sha: str
    subject: str
    group: str
    items: tuple[str, ...]


def run_git(repo: Path, args: list[str]) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True)


def find_previous_tag(repo: Path, current_tag: str) -> str | None:
    raw_tags = run_git(repo, ["tag", "--sort=-creatordate", "--list", "v*.*.*"])
    for tag in raw_tags.splitlines():
        tag = tag.strip()
        if tag != current_tag and SEMVER_TAG_RE.match(tag):
            return tag
    return None


def release_range(current_tag: str, previous_tag: str | None) -> str:
    if previous_tag:
        return f"{previous_tag}..{current_tag}"
    return current_tag


def parse_type_and_summary(subject: str) -> tuple[str | None, str]:
    match = CONVENTIONAL_RE.match(subject.strip())
    if not match:
        return None, subject.strip()
    return match.group("type").lower(), match.group("summary").strip()


def group_for_subject(subject: str) -> str:
    commit_type, _ = parse_type_and_summary(subject)
    if commit_type is None:
        return "其他"
    return TYPE_TO_GROUP.get(commit_type, "其他")


def clean_body_items(body: str) -> list[str]:
    items: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            items.append(" ".join(paragraph).strip())
            paragraph = []

    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line:
            flush_paragraph()
            continue
        if HEADING_ONLY_RE.match(line) or TRAILER_RE.match(line):
            flush_paragraph()
            continue

        list_match = LIST_ITEM_RE.match(line)
        if list_match:
            flush_paragraph()
            text = list_match.group("text").strip()
            if text:
                items.append(text)
        else:
            paragraph.append(line)

    flush_paragraph()

    deduped: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item and item not in seen:
            deduped.append(item)
            seen.add(item)
    return deduped


def items_for_commit(subject: str, body: str) -> tuple[str, ...]:
    _, summary = parse_type_and_summary(subject)
    items = clean_body_items(body)
    if not items and summary:
        items = [summary]
    return tuple(items)


def is_release_bump(subject: str) -> bool:
    return RELEASE_BUMP_RE.match(subject.strip()) is not None


def read_commits(repo: Path, current_tag: str, previous_tag: str | None) -> list[CommitNote]:
    log_format = "%x1e%H%x1f%s%x1f%b"
    raw_log = run_git(repo, ["log", "--no-merges", f"--pretty=format:{log_format}", release_range(current_tag, previous_tag)])
    notes: list[CommitNote] = []
    for record in raw_log.split("\x1e"):
        if not record.strip():
            continue
        parts = record.split("\x1f", 2)
        if len(parts) != 3:
            continue
        sha, subject, body = parts
        subject = subject.strip()
        if is_release_bump(subject):
            continue
        items = items_for_commit(subject, body)
        if not items:
            continue
        notes.append(CommitNote(sha=sha.strip(), subject=subject, group=group_for_subject(subject), items=items))
    return notes


def grouped_notes(notes: list[CommitNote]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {group: [] for group in GROUP_ORDER}
    for note in notes:
        grouped.setdefault(note.group, [])
        grouped[note.group].extend(note.items)
    return grouped


def render_markdown(grouped: dict[str, list[str]], previous_tag: str | None) -> str:
    lines = ["## 更新内容", ""]
    if previous_tag:
        lines.extend([f"自 [`{previous_tag}`]({RELEASE_REPO_URL}/releases/tag/{previous_tag}) 以来：", ""])

    wrote_group = False
    for group in GROUP_ORDER:
        items = grouped.get(group, [])
        if not items:
            continue
        wrote_group = True
        lines.extend([f"### {group}", ""])
        lines.extend(f"- {item}" for item in items)
        lines.append("")

    if not wrote_group:
        lines.append("- 本次发布没有源代码提交记录。")

    return "\n".join(lines).rstrip() + "\n"


def sparkle_items(grouped: dict[str, list[str]]) -> list[str]:
    items: list[str] = []
    for group in SPARKLE_PRIMARY_GROUPS:
        items.extend(grouped.get(group, []))
    if not items:
        for group in SPARKLE_FALLBACK_GROUPS:
            items.extend(grouped.get(group, []))
    return items[:8]


def render_sparkle_html(grouped: dict[str, list[str]]) -> str:
    items = sparkle_items(grouped)
    if not items:
        return "<h2>本次更新</h2>\n<p>本次发布包含稳定性和体验改进。</p>\n"

    lines = ["<h2>本次更新</h2>", "<ul>"]
    for item in items:
        lines.append(f"<li>{html.escape(item, quote=False)}</li>")
    lines.append("</ul>")
    return "\n".join(lines) + "\n"


def markdown_override_to_html(markdown_text: str) -> str:
    lines: list[str] = []
    paragraph: list[str] = []
    open_list: str | None = None

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            lines.append(f"<p>{html.escape(' '.join(paragraph), quote=False)}</p>")
            paragraph = []

    def close_list() -> None:
        nonlocal open_list
        if open_list:
            lines.append(f"</{open_list}>")
            open_list = None

    for raw_line in markdown_text.splitlines():
        line = raw_line.strip()
        if not line:
            flush_paragraph()
            close_list()
            continue

        heading = re.match(r"^(#{1,6})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            text = html.escape(heading.group(2).strip(), quote=False)
            lines.append(f"<h{level}>{text}</h{level}>")
            continue

        unordered = re.match(r"^[-*+]\s+(.+)$", line)
        ordered = re.match(r"^\d+[.)、]\s+(.+)$", line)
        list_match = unordered or ordered
        if list_match:
            flush_paragraph()
            target_list = "ul" if unordered else "ol"
            if open_list != target_list:
                close_list()
                lines.append(f"<{target_list}>")
                open_list = target_list
            text = html.escape(list_match.group(1).strip(), quote=False)
            lines.append(f"<li>{text}</li>")
            continue

        close_list()
        paragraph.append(line)

    flush_paragraph()
    close_list()
    return "\n".join(lines).strip() + "\n"


def read_sparkle_override(repo: Path, tag: str, override_dir: Path) -> str | None:
    base_dir = override_dir if override_dir.is_absolute() else repo / override_dir
    html_path = base_dir / f"{tag}.html"
    md_path = base_dir / f"{tag}.md"

    if html_path.exists():
        raw = html_path.read_text(encoding="utf-8").strip()
        if "]]>" in raw:
            raise ValueError(f"{html_path} contains ']]>', which would break appcast CDATA")
        return raw + "\n"

    if md_path.exists():
        raw = md_path.read_text(encoding="utf-8")
        if "]]>" in raw:
            raise ValueError(f"{md_path} contains ']]>', which would break appcast CDATA")
        return markdown_override_to_html(raw)

    return None


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="current release tag, e.g. v1.3.12")
    parser.add_argument("--markdown-out", required=True, type=Path)
    parser.add_argument("--sparkle-html-out", required=True, type=Path)
    parser.add_argument("--repo", default=Path.cwd(), type=Path)
    parser.add_argument("--sparkle-override-dir", default=Path("release-notes/sparkle"), type=Path)
    args = parser.parse_args()

    repo = args.repo.resolve()
    previous_tag = find_previous_tag(repo, args.tag)
    notes = read_commits(repo, args.tag, previous_tag)
    grouped = grouped_notes(notes)

    markdown = render_markdown(grouped, previous_tag)
    sparkle_html = read_sparkle_override(repo, args.tag, args.sparkle_override_dir)
    if sparkle_html is None:
        sparkle_html = render_sparkle_html(grouped)
    if "]]>" in sparkle_html:
        print("error: Sparkle release notes contain ']]>', which would break appcast CDATA", file=sys.stderr)
        return 1

    write_text(args.markdown_out, markdown)
    write_text(args.sparkle_html_out, sparkle_html)
    print(f"generated {args.markdown_out} and {args.sparkle_html_out}")
    if previous_tag:
        print(f"commit range: {previous_tag}..{args.tag}")
    else:
        print(f"commit range: {args.tag}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"error: git command failed with exit code {error.returncode}: {' '.join(error.cmd)}", file=sys.stderr)
        if error.output:
            print(error.output, file=sys.stderr)
        raise SystemExit(error.returncode)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
