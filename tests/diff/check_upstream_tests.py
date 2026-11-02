#!/usr/bin/env python3
"""
Check upstream (vim-skk/skkeleton) test cases against tests/README.md.

Usage:
    python3 tests/diff/check_upstream_tests.py [UPSTREAM_DIR]

If UPSTREAM_DIR is not specified or found, skips gracefully with exit code 0.
"""

import glob
import os
import re
import sys

CANDIDATE_PATHS = [
    os.environ.get("SKKELETON_UPSTREAM_DIR"),
    os.path.expanduser("~/.local/share/nvim/lazy/skkeleton"),
    "/tmp/skkeleton",
]


def find_upstream_dir():
    if len(sys.argv) > 1:
        custom = sys.argv[1]
        if os.path.isdir(custom):
            return custom
        print(f"Specified upstream directory not found: {custom}")
        return None
    for p in CANDIDATE_PATHS:
        if p and os.path.isdir(p):
            return p
    return None


def extract_upstream_tests(upstream_dir):
    pattern = os.path.join(upstream_dir, "denops/**/*_test.ts")
    files = sorted(glob.glob(pattern, recursive=True))
    cases = []
    # Match double-quoted, single-quoted, or backtick-quoted names
    regex = re.compile(
        r'(?:test\s*\(\s*\{[^}]*?name:\s*|Deno\.test\s*\(\s*(?:\{\s*name:\s*)?)(?:"([^"]+)"|\'([^\']+)\'|`([^`]+)`)',
        re.DOTALL,
    )
    for f in files:
        rel = os.path.relpath(f, upstream_dir)
        with open(f, "r", encoding="utf-8") as fp:
            content = fp.read()
        for m in regex.finditer(content):
            name = m.group(1) or m.group(2) or m.group(3)
            cases.append((rel, name))
    return cases


def load_readme_cases(readme_path):
    if not os.path.isfile(readme_path):
        return set()
    with open(readme_path, "r", encoding="utf-8") as fp:
        content = fp.read()
    # Table rows: | `file` | `case` | ...
    table_regex = re.compile(r"\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|")
    found = set()
    for row in table_regex.finditer(content):
        found.add((row.group(1), row.group(2)))
    return found


def main():
    upstream_dir = find_upstream_dir()
    if not upstream_dir:
        print("Upstream directory not found; skipping upstream test comparison.")
        sys.exit(0)

    readme_path = os.path.join(
        os.path.dirname(__file__), "..", "..", "tests", "README.md"
    )
    readme_path = os.path.normpath(readme_path)
    known_cases = load_readme_cases(readme_path)

    upstream_cases = extract_upstream_tests(upstream_dir)
    print(
        f"Found {len(upstream_cases)} test cases in upstream ({upstream_dir})."
    )

    untracked = []
    for rel_file, case_name in upstream_cases:
        if (rel_file, case_name) not in known_cases:
            untracked.append((rel_file, case_name))

    if untracked:
        print(f"\n[WARNING] {len(untracked)} cases not in tests/README.md:")
        for rel_file, case_name in untracked:
            print(f"  - {rel_file}: {case_name}")
    else:
        print("\nAll upstream test cases are tracked in tests/README.md.")


if __name__ == "__main__":
    main()
