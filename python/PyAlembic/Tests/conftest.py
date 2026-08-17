"""pytest bootstrap for the wheel test-command.

The wheel installs the PyAlembic extension under a renamed import name (the
``PYALEMBIC_MODULE_NAME`` knob in ``pyproject.toml``, ``alembic3d`` by default)
plus the bundled ``imath`` module. The upstream test files in this directory
import ``alembic`` and ``imath`` by their original names, so this conftest —
which pytest imports before collecting any test module — aliases the installed
module back to ``alembic`` and imports ``imath``.

The import name is read from the single source of truth (the pyproject knob),
honouring the ``PYALEMBIC_MODULE_NAME`` build-time env override, so there is no
second place to update on a rename. ``tomllib`` is stdlib on 3.11+; on 3.10 the
``tomli`` backport is pulled in via cibuildwheel ``test-requires``.
"""
import importlib
import os
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10
    import tomli as tomllib

# conftest.py -> Tests -> PyAlembic -> python -> <repo root>
REPO_ROOT = Path(__file__).resolve().parents[3]
PYPROJECT = REPO_ROOT / "pyproject.toml"


def _import_name() -> str:
    """Resolve the installed top-level import name from the single source.

    Mirrors how scikit-build-core resolves the ``{ env = ..., default = ... }``
    cmake define: the env var wins, otherwise the declared default.
    """
    with PYPROJECT.open("rb") as fh:
        define = tomllib.load(fh)["tool"]["scikit-build"]["cmake"]["define"]
    knob = define["PYALEMBIC_MODULE_NAME"]
    if isinstance(knob, dict):
        env_name = knob.get("env")
        override = os.environ.get(env_name) if env_name else None
        return override or knob["default"]
    return knob


_name = _import_name()

# Importing the top module also registers its Boost.Python submodules
# (<name>.Abc, <name>.AbcGeom, ...) in sys.modules.
importlib.import_module(_name)

# Alias <name>[.sub] -> alembic[.sub] so the upstream tests import unmodified.
if _name != "alembic":
    for mod in list(sys.modules):
        if mod == _name or mod.startswith(_name + "."):
            sys.modules["alembic" + mod[len(_name):]] = sys.modules[mod]

# imath is bundled inside the wheel; fail loudly here if it is missing.
import imath  # noqa: E402,F401
