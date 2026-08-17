#!/usr/bin/env python
"""Emit the CI wheel-build Python matrix from the single source of truth.

The set of CPython versions to build is declared exactly once, in
``[tool.cibuildwheel].build`` in the repo-root ``pyproject.toml`` (e.g.
``["cp310-*", "cp311-*", "cp312-*", "cp313-*"]``). The GitHub Actions workflow
used to duplicate that list as a hardcoded job matrix; instead it now calls this
script, so changing the Python set is a one-line edit in ``pyproject.toml``.

Output: a JSON array of the unique ``cpXY`` interpreter tags, e.g.
``["cp310", "cp311", "cp312", "cp313"]``. When ``$GITHUB_OUTPUT`` is set (inside
Actions) it also appends ``py=<json>`` there for ``fromJSON`` to consume.

Run locally to see what the matrix will expand to:

    python scripts/ci/compute_matrix.py
"""
import json
import os
import re
import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PYPROJECT = REPO_ROOT / "pyproject.toml"

# Leading interpreter tag of a cibuildwheel build identifier / selector:
# "cp310-*" -> "cp310", "cp313-manylinux_x86_64" -> "cp313". Free-threaded
# builds ("cp313t-*") are excluded by [tool.cibuildwheel].skip, so a plain
# cpXY match is sufficient here.
TAG_RE = re.compile(r"^(cp\d+)")


def interpreter_tags(build) -> list[str]:
    """Unique cpXY tags from a cibuildwheel ``build`` value, version-ordered.

    ``build`` may be a list of selectors or a single whitespace-separated
    string (cibuildwheel accepts both).
    """
    if isinstance(build, str):
        selectors = build.split()
    else:
        selectors = list(build)

    tags: list[str] = []
    for selector in selectors:
        match = TAG_RE.match(selector.strip())
        if match and match.group(1) not in tags:
            tags.append(match.group(1))

    # Sort by numeric Python version so job order is stable and readable.
    tags.sort(key=lambda t: int(t[2:]))
    return tags


def main() -> int:
    with PYPROJECT.open("rb") as fh:
        config = tomllib.load(fh)

    try:
        build = config["tool"]["cibuildwheel"]["build"]
    except KeyError:
        print(
            "error: [tool.cibuildwheel].build is missing from pyproject.toml",
            file=sys.stderr,
        )
        return 1

    tags = interpreter_tags(build)
    if not tags:
        print(
            f"error: no cpXY interpreter tags found in build={build!r}",
            file=sys.stderr,
        )
        return 1

    payload = json.dumps(tags)
    print(payload)

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(f"py={payload}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
