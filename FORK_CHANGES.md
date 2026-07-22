# Fork changes: `alembic3d` Python wheels

This fork adds continuous Python **wheel** builds for the PyAlembic bindings,
published under the distribution/import name **`alembic3d`** so they do not
clash with SQLAlchemy's `alembic` on PyPI or at import time:

```python
pip install alembic3d
import alembic3d
from alembic3d.Abc import *
from alembic3d.AbcGeom import *
import imath          # PyImath, bundled inside the wheel
```

Everything here is **additive** and, where upstream files had to change, the
edits are minimal and preserve upstream behaviour by default (a normal
`-DUSE_PYALEMBIC=ON` build still produces a module named `alembic`). This is to
keep future merges from `AcademySoftwareFoundation/alembic` low-friction.

The changes below are the complete diff against the upstream `master` this fork
was branched from.

---

## New files

| File | Purpose |
|------|---------|
| `pyproject.toml` | scikit-build-core build config + all cibuildwheel settings (matrix, per-OS dependency env, repair commands). Single source of the package name; version is read from the CMake `project()` call. |
| `.github/workflows/wheels.yml` | CI: builds wheels for Windows / Linux (manylinux) / macOS across CPython 3.10–3.13 via `pypa/cibuildwheel`, uploads them as artifacts. Contains a commented-out PyPI-publish job for later. |
| `cmake/PyAlembicWheel.cmake` | Bundles the prebuilt PyImath `imath` extension into the wheel. No-op outside scikit-build wheel builds. |
| `scripts/ci/wheel_deps_prepare.sh` | cibuildwheel `before-all`: downloads Boost + Imath sources, bootstraps Boost's `b2`, patches Imath's Python CMake for manylinux. |
| `scripts/ci/wheel_deps_build.sh` | cibuildwheel `before-build`: builds **shared** Boost.Python + Imath/PyImath against the exact target CPython. |
| `scripts/ci/run_wheel_tests.py` | cibuildwheel `test-command`: aliases `alembic3d` back to `alembic` and runs the upstream `RunTests.py` suite unmodified. |
| `scripts/ci/README.md` | Documents the CI dependency scripts and the shared-library requirement. |
| `.gitattributes` | Forces `*.sh` to LF so the shell scripts run on the Linux/macOS runners. |
| `FORK_CHANGES.md` | This document. |

## Modified upstream files

### `CMakeLists.txt` (root) — 1 line
`FIND_PACKAGE(Python COMPONENTS Interpreter Development)` →
`... Development.Module`. The full `Development` component needs libpython
artifacts the manylinux images do not ship; `Development.Module` is the correct
component for building extension modules and works everywhere.

### `python/PyAlembic/CMakeLists.txt`
- `Python::Python` → `Python::Module` in `TARGET_LINK_LIBRARIES`. Extension
  modules must not link libpython, or auditwheel rejects the wheel.
- The install destination is now SKBUILD-aware: under scikit-build it installs
  the module to the absolute `${SKBUILD_PLATLIB_DIR}` (the wheel's platlib
  root). This avoids a CMake gotcha where `ALEMBIC_PYTHON_INSTALL_DIR` is a
  `CACHE PATH`, so a relative `-D` value (`.`) gets rewritten to an absolute
  source-tree path — which silently produced an **empty wheel**. The non-wheel
  path keeps the original `lib/pythonX.Y/site-packages` default.
- Added a `PYALEMBIC_MODULE_NAME` cache variable (default `"alembic"`). When set
  to something else, the target's `OUTPUT_NAME` and a `PYALEMBIC_MODULE_NAME`
  compile definition are set so the module is renamed.
- `INCLUDE`s the new `cmake/PyAlembicWheel.cmake`.

### `python/PyAlembic/main.cpp`
Made the module name configurable at compile time. Added a small macro block
(default `PYALEMBIC_MODULE_NAME` = `alembic`), changed
`BOOST_PYTHON_MODULE( alembic )` to `BOOST_PYTHON_MODULE( PYALEMBIC_MODULE_NAME )`,
and replaced the hardcoded `"alembic.<submodule>"` strings (the package
`__path__` and the `AbcCoreAbstract`/`Util`/`Abc`/`AbcGeom`/`AbcCollection`/
`AbcMaterial` module names) with `PYALEMBIC_MODULE_NAME_STR ".<submodule>"`.
`BOOST_PYTHON_MODULE` macro-expands its argument, so the compile define renames
both the module and its init function.

### `cmake/AlembicPyIlmBase.cmake`
Made PyImath discovery robust. A from-source Imath 3.1 build installs the
`libPyImath_Python<x>_<y>` shared library but its `install(TARGETS)` has **no
`EXPORT`**, so neither `Imath::PyImath` nor `Imath::PyImath_Python3_12` is
importable and Alembic's configure failed with "target not found". The logic now
tries the imported targets first (unchanged behaviour where Imath exports them),
then falls back to `find_library` on the version-suffixed soname and propagates
Imath's include dirs so the PyImath headers are found.

### `python/PyAlembic/Tests/{testCollections,testCurves,testTypes,testPropExcept}.py`
Replaced `assertEquals` → `assertEqual` and `failUnlessRaises` → `assertRaises`.
These unittest aliases were removed in Python 3.12; the change lets the upstream
test suite run on the versions we build (3.10–3.13). No test logic changes.

## Deleted files

| File | Why |
|------|-----|
| `setup.py` | Stale Python-2.7-era CMake shim (hardcoded version, copied `.so` from `/usr/local/lib/python2.7`). Replaced by `pyproject.toml`. |
| `.github/actions/build-manylinux/` | Old Python 2.7 / Boost 1.55 / IlmBase 2.2 manylinux action, superseded by the cibuildwheel workflow. |

---

## How the wheel is built

1. **cibuildwheel** drives the whole matrix (config in `pyproject.toml`).
2. Per job: `wheel_deps_prepare.sh` fetches Boost + Imath sources.
3. Per Python version: `wheel_deps_build.sh` builds **shared** Boost.Python and
   Imath/PyImath against that interpreter into a fixed prefix.
4. **scikit-build-core** builds Alembic with `USE_PYALEMBIC=ON`,
   `ALEMBIC_SHARED_LIBS=OFF` (static core), `PYALEMBIC_MODULE_NAME=alembic3d`,
   producing the `alembic3d` extension and bundling the `imath` extension.
5. The repair tools (auditwheel / delocate / delvewheel) vendor the shared
   Boost.Python, PyImath and Imath libraries into the wheel.
6. `run_wheel_tests.py` installs the wheel and runs the upstream test suite.

### Why Boost.Python and PyImath must be shared, and `imath` ships in the wheel
Boost.Python keeps a single global type-converter registry inside
`libboost_python`. PyImath registers Imath↔Python converters into it, and the
`alembic3d` extension imports `imath` at init. If either were static, the two
extensions would get separate registries and cross-module conversion would fail.
Both extensions must therefore resolve to the same shared libraries, and the
`imath` extension is bundled in the same wheel.

## Platform coverage
- **Linux** — manylinux_2_28, x86_64.
- **Windows** — x86_64 (MSVC).
- **macOS** — arm64 only. GitHub retired the free Intel `macos-13` runner and
  Intel macOS is now paid-only, so x86_64 macOS wheels are not built; Intel Mac
  users can build from source.
- **Python** — CPython 3.10–3.13.

## Building one wheel locally
See `scripts/ci/README.md`. On Windows, from a target-Python venv with VS 2022
and Git Bash:
```bash
export DEPS_DIR=C:/wheel-deps DEPS_SRC=C:/wheel-deps-src
bash scripts/ci/wheel_deps_prepare.sh
bash scripts/ci/wheel_deps_build.sh
pipx run cibuildwheel --only cp312-win_amd64
```

## Notes for merging upstream
- The upstream-file edits are intentionally small and default to upstream
  behaviour; conflicts should be rare and localised.
- `wheel_deps_prepare.sh` patches Imath's Python CMake with `sed` rather than a
  context diff, so it tolerates minor Imath reformatting. Dependency versions
  (`BOOST_VERSION`, `IMATH_VERSION`) are pinned there and overridable by env.
- Keep using Imath's Boost `PyImath` (`-DPYTHON=ON`); Alembic links
  `Imath::PyImath`. Imath 3.2+ adds a separate pybind11 `PyBindImath` that is
  not a drop-in replacement.
