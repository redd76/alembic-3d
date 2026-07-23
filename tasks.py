"""Developer task runner for the alembic3d wheel build (footman).

Convenience wrappers over cibuildwheel and the CI dependency scripts for local
work: `fm identifiers`, `fm matrix`, `fm deps`, `fm wheel`, `fm test-local`.

This layer is DEV-ONLY. CI (.github/workflows/wheels.yml) invokes cibuildwheel
directly and never depends on footman — footman needs Python >= 3.11, while the
wheels themselves are built/tested down to cp310. Install it with
`pip install footman` (or the pinned dev group in pyproject.toml).
"""
from __future__ import annotations

import os
from pathlib import Path

from footman import run, task

REPO_ROOT = Path(__file__).resolve().parent


def _deps_env() -> dict[str, str]:
    """Environment for the dep scripts, with local-dev defaults.

    Mirrors the fixed-prefix scheme the scripts expect (see scripts/ci). Any
    value already set in the environment wins, so a machine-specific prefix can
    be exported ahead of time.
    """
    env = dict(os.environ)
    env.setdefault("DEPS_DIR", str(Path.home() / "wheel-deps"))
    env.setdefault("DEPS_SRC", str(Path.home() / "wheel-deps-src"))
    return env


@task
def identifiers() -> None:
    "Print the cibuildwheel build identifiers for this machine's platform."
    run("cibuildwheel --print-build-identifiers", capture=False)


@task
def matrix() -> None:
    "Show the CI Python matrix derived from pyproject (scripts/ci/compute_matrix.py)."
    run("python scripts/ci/compute_matrix.py", capture=False)


@task
def deps() -> None:
    "Build the local Boost.Python + Imath/PyImath dependency prefix."
    env = _deps_env()
    run("bash scripts/ci/wheel_deps_prepare.sh", env=env, capture=False)
    run("bash scripts/ci/wheel_deps_build.sh", env=env, capture=False)


@task
def wheel(only: str = "") -> None:
    """Build wheel(s) with cibuildwheel; pass only=<identifier> for a single build.

    cibuildwheel runs the pytest test-command against each freshly built wheel,
    so this both builds and tests.
    """
    cmd = "cibuildwheel"
    if only:
        cmd += f" --only {only}"
    run(cmd, capture=False)
