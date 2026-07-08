#!/usr/bin/env python3
"""
Add copyright headers to BrightScript (.brs) and XML (.xml) source files.
Idempotent: skips files that already contain the copyright notice.
"""

import os
import re
import sys
from pathlib import Path

COPYRIGHT = "copyright 2026 Joe Huss"
COPYRIGHT_UPPER = COPYRIGHT.upper()

EXCLUDED_DIRS = {"vendor", ".git", "node_modules", "dist", "generated", ".github", "__pycache__", ".logs", ".opencode", ".caliber"}

BRIGHT_SCRIPT_EXTENSIONS = {".brs"}
XML_EXTENSIONS = {".xml"}

COMMENT_BLOCKS_BRS = """' {copyright}
'
""".format(copyright=COPYRIGHT)

COMMENT_BLOCK_XML = """<!-- {copyright} -->
""".format(copyright=COPYRIGHT)


def get_comment_block(ext: str) -> str:
    if ext in BRIGHT_SCRIPT_EXTENSIONS:
        return COMMENT_BLOCKS_BRS
    return COMMENT_BLOCK_XML


def has_copyright(content: str) -> bool:
    return COPYRIGHT_UPPER in content.upper()


def needs_header(filepath: Path) -> bool:
    ext = filepath.suffix.lower()
    return ext in BRIGHT_SCRIPT_EXTENSIONS | XML_EXTENSIONS


def process_file(filepath: Path) -> tuple[bool, bool]:
    """
    Returns (updated, skipped).
    updated=True means file was modified.
    skipped=True means file already had copyright (not modified).
    """
    ext = filepath.suffix.lower()
    if not needs_header(filepath):
        return False, True

    content = filepath.read_text(encoding="utf-8")

    if has_copyright(content):
        return False, True

    comment_block = get_comment_block(ext)

    # For .brs files, insert after any shebang/XML declaration at the top
    # For .xml files, insert after <?xml ...?> declaration
    lines = content.splitlines()
    new_lines = []

    if ext == ".xml" and lines and lines[0].startswith("<?xml"):
        new_lines.append(lines[0])
        new_lines.append("")
        new_lines.append(comment_block)
        new_lines.extend(lines[1:])
    elif ext == ".brs":
        # For .brs, insert after first line if it's a comment (common pattern: ' filename.brs)
        # otherwise at the very top
        if lines and lines[0].startswith("'"):
            new_lines.append(lines[0])
            new_lines.append("")
            new_lines.append(comment_block)
            new_lines.extend(lines[1:])
        else:
            new_lines.append(comment_block)
            new_lines.extend(lines)
    else:
        new_lines.append(comment_block)
        new_lines.extend(lines)

    new_content = "\n".join(new_lines)
    # Normalize line endings
    if "\r\n" in content:
        new_content = new_content.replace("\n", "\r\n")

    filepath.write_text(new_content, encoding="utf-8")
    return True, False


def find_source_files(root: Path) -> list[Path]:
    """Recursively find all source files, excluding certain directories."""
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Filter out excluded directories in-place
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
        for filename in filenames:
            filepath = Path(dirpath) / filename
            if needs_header(filepath):
                files.append(filepath)
    return sorted(files)


def main():
    repo_root = Path(__file__).parent.parent
    source_dirs = [repo_root / "source", repo_root / "components", repo_root / "tests"]

    all_files = []
    for d in source_dirs:
        if d.exists():
            all_files.extend(find_source_files(d))

    updated = 0
    skipped = 0

    for filepath in all_files:
        was_updated, was_skipped = process_file(filepath)
        if was_updated:
            updated += 1
            print(f"  UPDATED: {filepath.relative_to(repo_root)}")
        else:
            skipped += 1

    print(f"{updated} files updated, {skipped} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
