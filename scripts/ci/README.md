# CI wheel-build scripts

These scripts drive `cibuildwheel` to produce `alembic3d` wheels (the PyAlembic
bindings under a non-clashing name). All `cibuildwheel` configuration lives in
the repo-root `pyproject.toml`, so a local run matches CI exactly.

| Script | cibuildwheel hook | Runs | Purpose |
|--------|-------------------|------|---------|
| `wheel_deps_prepare.sh` | `before-all` | once per OS | Download Boost + Imath sources, bootstrap b2, patch Imath's python CMake for manylinux |
| `wheel_deps_build.sh` | `before-build` | once per Python version | Build **shared** Boost.Python + Imath/PyImath against that interpreter into `DEPS_DIR` |
| `compute_matrix.py` | (CI matrix) | once per workflow | Emit the CPython version matrix from `[tool.cibuildwheel].build` so `wheels.yml` never hardcodes it |

The `test-command` is `pytest` (configured in `pyproject.toml`); the upstream
suite is bootstrapped by `python/PyAlembic/Tests/conftest.py`, which aliases the
renamed module back to `alembic` and imports the bundled `imath`.

## Dependency version pins

Overridable via environment variables (defaults in `wheel_deps_prepare.sh`):

- `BOOST_VERSION` (default `1.87.0`)
- `IMATH_VERSION` (default `3.1.12`)

Keep using Imath's Boost-based `PyImath` (`-DPYTHON=ON`); Alembic links
`Imath::PyImath`. Imath 3.2+ adds a separate pybind11 `PyBindImath` that is
**not** a drop-in replacement.

## Why shared libraries are mandatory

Boost.Python keeps a single global type-converter registry inside
`libboost_python`. PyImath registers Imath<->Python converters into it, and the
`alembic3d` extension imports `imath` at init time. If Boost.Python or PyImath
were static, the `imath` and `alembic3d` extensions would each get their own
registry and cross-module conversion would silently fail. Both extensions must
resolve to the same shared `libboost_python` / `libPyImath`, which is why the
repair tools (auditwheel / delocate / delvewheel) vendor exactly one copy of
each and the `imath` extension ships inside the same wheel.

## Local build (Windows example)

From a target-Python venv with Visual Studio 2022 + Git Bash on PATH:

```bash
export DEPS_DIR=C:/wheel-deps DEPS_SRC=C:/wheel-deps-src
bash scripts/ci/wheel_deps_prepare.sh
bash scripts/ci/wheel_deps_build.sh
```

Then run the full pipeline (build + delvewheel repair + tests) via:

```bash
pipx run cibuildwheel --only cp312-win_amd64
```
