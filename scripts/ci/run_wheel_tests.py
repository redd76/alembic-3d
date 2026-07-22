#!/usr/bin/env python
"""cibuildwheel test-command for the alembic3d wheel.

The wheel installs the extension under the renamed import name (``alembic3d``)
plus the bundled ``imath`` module. The upstream test suite in
``python/PyAlembic/Tests`` imports ``alembic`` and ``imath`` by their original
names, so we alias the installed module back to ``alembic`` and then run the
unchanged upstream ``RunTests.py`` harness.

Run from anywhere; paths are resolved relative to this file.
"""
import importlib
import os
import runpy
import sys

MODULE_NAME = os.environ.get("PYALEMBIC_MODULE_NAME", "alembic3d")

# Importing the top module also registers its Boost.Python submodules
# (alembic3d.Abc, alembic3d.AbcGeom, ...) in sys.modules.
importlib.import_module(MODULE_NAME)

# Alias alembic3d[.X] -> alembic[.X] so upstream tests import unmodified.
for name in list(sys.modules):
    if name == MODULE_NAME or name.startswith(MODULE_NAME + "."):
        alias = "alembic" + name[len(MODULE_NAME):]
        sys.modules[alias] = sys.modules[name]

# imath is bundled inside the wheel; fail loudly here if it is missing.
import imath  # noqa: E402,F401

repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
tests_dir = os.path.join(repo_root, "python", "PyAlembic", "Tests")
run_tests = os.path.join(tests_dir, "RunTests.py")

# RunTests.py signature: RunTests.py <alembic_path> <imath_path> [testfiles...]
# Both path args are already importable (installed wheel), so pass no-ops.
sys.argv = [run_tests, ".", "."]
runpy.run_path(run_tests, run_name="__main__")
