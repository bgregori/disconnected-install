#!/usr/bin/env python3
"""Consistency checks for the documentation itself.

Not an install-host script. This one runs on a laptop or in CI, touches
nothing outside the repository, and is unnumbered because it is not part
of the execution order in scripts/README.md.

It exists because this repository's central claim -- that you can tell a
verified command from a drafted one -- is maintained by hand, and in the
first drafting pass the hand-maintained draft count had already drifted
by one. A count that is wrong in the direction of "fewer drafts than
there are" is the specific failure VALIDATION.md is built to prevent, and
it is not a failure a reader can detect.

Checks, in order of how much they matter:

  drafts   every 🚧 DRAFT marker is counted, per chapter, and reconciled
           against VALIDATION.md's table and README.md's headline
  hosts    every sh/bash/yaml block opens with a RUN ON / EDIT IN marker
  links    every relative link resolves, file and heading anchor both

Exit status is the number of failing checks, so it is 0 when clean.

    ./scripts/check-docs.py
    ./scripts/check-docs.py --quiet     # findings only
"""

import argparse
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The marker as it appears at the point of use. Matched on the literal
# string rather than loosely on "DRAFT", so that prose *about* drafts --
# the convention sections in README and VALIDATION, the checklist item
# about reconciling them -- does not inflate the count. That distinction
# is what the first drift was made of.
DRAFT_MARKER = re.compile(r"🚧 \*\*DRAFT")

# Chapters carry drafts and are counted. Everything else is prose about
# the scheme rather than subject to it.
COUNTED_DIRS = ("docs",)

HOST_MARKER = re.compile(r"=====\s*(RUN ON|EDIT IN):")
FENCE = re.compile(r"^(\s*)```(\S*)")
LINK = re.compile(r"\]\(([^)]+)\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")

# Fences whose first line must say where the block runs. A block with no
# language is prose or a directory tree; a `text` block is output.
MARKED_LANGS = {"sh", "bash", "yaml", "yml"}


def red(s):
    return f"\033[31m{s}\033[0m" if sys.stderr.isatty() else s


def green(s):
    return f"\033[32m{s}\033[0m" if sys.stderr.isatty() else s


def markdown_files():
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in sorted(filenames):
            if name.endswith(".md"):
                yield os.path.join(dirpath, name)


def rel(path):
    return os.path.relpath(path, REPO_ROOT)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def outside_fences(text):
    """Yield (lineno, line) for lines that are not inside a code fence."""
    inside = False
    for number, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            inside = not inside
            continue
        if not inside:
            yield number, line


def slug(heading):
    """GitHub's heading anchor.

    Each space becomes one hyphen -- collapsing runs of whitespace is
    wrong, and silently reports every `## Step 7 — delete kubeadmin`
    link as broken, which is how an hour goes missing.
    """
    text = heading.lower()
    text = re.sub(r"[`*_\[\]()]", "", text)
    text = re.sub(r"[^\w\s-]", "", text)
    return text.strip().replace(" ", "-")


def anchors(path, _cache={}):  # noqa: B006 -- deliberate memo
    if path in _cache:
        return _cache[path]
    found = set()
    if path.endswith(".md") and os.path.exists(path):
        for _, line in outside_fences(read(path)):
            match = HEADING.match(line)
            if match:
                found.add(slug(match.group(2)))
    _cache[path] = found
    return found


# --- checks ----------------------------------------------------------------


def check_drafts():
    """Reconcile the draft count against the two places that state it."""
    problems = []

    counts = {}
    for path in markdown_files():
        if rel(path).split(os.sep)[0] not in COUNTED_DIRS:
            continue
        counts[rel(path)] = len(DRAFT_MARKER.findall(read(path)))
    total = sum(counts.values())

    validation = read(os.path.join(REPO_ROOT, "VALIDATION.md"))

    # The per-chapter table: | [NN Name](docs/foo.md) | 7 | prose |
    row = re.compile(r"^\|\s*\[[^\]]+\]\((docs/[^)]+\.md)\)\s*\|\s*(\d+)\s*\|")
    claimed = {}
    for line in validation.split("\n"):
        match = row.match(line)
        if match:
            claimed[match.group(1)] = int(match.group(2))

    if not claimed:
        problems.append(
            "VALIDATION.md: found no per-chapter draft table. The table is "
            "how the count is published; if its shape changed, this check "
            "needs changing with it."
        )

    for path, actual in sorted(counts.items()):
        if path not in claimed:
            problems.append(
                f"{path}: has {actual} draft(s) but no row in VALIDATION.md's table"
            )
        elif claimed[path] != actual:
            problems.append(
                f"{path}: {actual} draft marker(s) in the file, "
                f"VALIDATION.md's table claims {claimed[path]}"
            )
    for path in sorted(set(claimed) - set(counts)):
        problems.append(f"VALIDATION.md: table has a row for {path}, which does not exist")

    # The two headline totals, stated as prose in both files.
    headline = re.compile(r"\*\*(\d+) (?:of them are marked|drafted blocks)")
    for name in ("README.md", "VALIDATION.md"):
        text = read(os.path.join(REPO_ROOT, name))
        stated = [int(n) for n in headline.findall(text)]
        if not stated:
            problems.append(
                f"{name}: no headline draft count found. It is the first "
                f"thing a reader sees; it is not optional."
            )
        for value in stated:
            if value != total:
                problems.append(
                    f"{name}: headline says {value} drafts, actual total is {total}"
                )

    return problems, f"{total} draft markers, reconciled across {len(counts)} chapters"


def check_host_markers():
    """Every runnable block says where it runs, on its first line."""
    problems = []
    blocks = 0

    for path in markdown_files():
        if rel(path).split(os.sep)[0] not in COUNTED_DIRS:
            continue
        lines = read(path).split("\n")
        index = 0
        while index < len(lines):
            fence = FENCE.match(lines[index])
            if fence and fence.group(2) in MARKED_LANGS:
                blocks += 1
                first = lines[index + 1] if index + 1 < len(lines) else ""
                if not HOST_MARKER.search(first):
                    problems.append(
                        f"{rel(path)}:{index + 1}: ```{fence.group(2)} block does not "
                        f"open with a RUN ON / EDIT IN marker"
                    )
                index += 1
                while index < len(lines) and not FENCE.match(lines[index]):
                    index += 1
            index += 1

    return problems, f"{blocks} runnable blocks, all labelled with a host"


def check_links():
    """Relative links resolve, to a file and to a heading."""
    problems = []
    checked = 0

    for path in markdown_files():
        directory = os.path.dirname(path)
        for number, line in enumerate(read(path).split("\n"), 1):
            for target in LINK.findall(line):
                target = target.split()[0]
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                checked += 1
                filename, _, fragment = target.partition("#")
                resolved = (
                    os.path.normpath(os.path.join(directory, filename))
                    if filename
                    else path
                )
                if filename and not os.path.exists(resolved):
                    problems.append(f"{rel(path)}:{number}: no such file -- {target}")
                elif fragment and resolved.endswith(".md"):
                    if fragment not in anchors(resolved):
                        problems.append(
                            f"{rel(path)}:{number}: no such heading -- {target}"
                        )

    return problems, f"{checked} relative links resolve"


CHECKS = (
    ("drafts", check_drafts),
    ("hosts", check_host_markers),
    ("links", check_links),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--quiet", action="store_true", help="findings only")
    args = parser.parse_args()

    failed = 0
    for name, check in CHECKS:
        problems, summary = check()
        if problems:
            failed += 1
            print(red(f"[FAIL]  {name}"), file=sys.stderr)
            for problem in problems:
                print(f"          {problem}", file=sys.stderr)
        elif not args.quiet:
            print(green(f"[ OK ]  {name}") + f"  {summary}", file=sys.stderr)

    if failed and not args.quiet:
        print(
            "\nA draft count that drifts low is the one defect in this "
            "repository\nthat a reader cannot detect. See VALIDATION.md.",
            file=sys.stderr,
        )
    return failed


if __name__ == "__main__":
    sys.exit(main())
