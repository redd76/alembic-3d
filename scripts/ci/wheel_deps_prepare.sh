#!/usr/bin/env bash
#
# cibuildwheel "before-all" step (runs ONCE per job / OS).
#
# Downloads and unpacks the native dependencies that the PyAlembic wheel needs
# built against the target CPython:
#   * Boost.Python  (shared)
#   * Imath + PyImath (shared)
#
# The actual per-Python-version compile happens in wheel_deps_build.sh; here we
# only fetch sources, bootstrap Boost's build system, and patch Imath's python
# CMake so it works inside manylinux (no libpython link).
#
# Env (set by pyproject.toml [tool.cibuildwheel.<os>].environment):
#   DEPS_SRC    where sources are unpacked (constant per job)
# Overridable pins:
#   BOOST_VERSION   default 1.87.0
#   IMATH_VERSION   default 3.1.12
set -euo pipefail

BOOST_VERSION="${BOOST_VERSION:-1.87.0}"
IMATH_VERSION="${IMATH_VERSION:-3.1.12}"
DEPS_SRC="${DEPS_SRC:?DEPS_SRC must be set}"

# If the compiled deps are already present (restored from the CI cache), there
# is nothing to download or bootstrap.
if [ -n "${DEPS_DIR:-}" ] && [ -f "${DEPS_DIR}/.complete" ]; then
    echo "== wheel_deps_prepare: cached deps at ${DEPS_DIR}, skipping source prep =="
    exit 0
fi

BOOST_UNDERSCORE="boost_${BOOST_VERSION//./_}"

echo "== wheel_deps_prepare: Boost ${BOOST_VERSION}, Imath ${IMATH_VERSION} =="
rm -rf "${DEPS_SRC}"
mkdir -p "${DEPS_SRC}"
cd "${DEPS_SRC}"

# --- download ---------------------------------------------------------------
# curl is present on all GitHub runners and in the manylinux images.
BOOST_URL="https://archives.boost.io/release/${BOOST_VERSION}/source/${BOOST_UNDERSCORE}.tar.gz"
IMATH_URL="https://github.com/AcademySoftwareFoundation/Imath/archive/refs/tags/v${IMATH_VERSION}.tar.gz"

echo "Downloading Boost from ${BOOST_URL}"
curl -fsSL "${BOOST_URL}" -o boost.tar.gz
echo "Downloading Imath from ${IMATH_URL}"
curl -fsSL "${IMATH_URL}" -o imath.tar.gz

tar xzf boost.tar.gz
tar xzf imath.tar.gz
mv "${BOOST_UNDERSCORE}" boost
mv "Imath-${IMATH_VERSION}" imath

# --- bootstrap Boost b2 -----------------------------------------------------
cd "${DEPS_SRC}/boost"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        cmd //c bootstrap.bat
        ;;
    *)
        ./bootstrap.sh
        ;;
esac

# --- patch Imath's python CMake so it never links libpython -----------------
# The full "Development" component and Python3::Python link make manylinux
# configure fail / produce auditwheel-rejected wheels. Rewrite to the
# module-only equivalents. sed edits (rather than a context-diff patch) so
# this survives minor Imath reformatting across versions.
PYDIR="${DEPS_SRC}/imath/src/python"
if [[ -d "${PYDIR}" ]]; then
    # find_package(PythonN COMPONENTS Interpreter Development) -> Development.Module
    find "${PYDIR}" -name 'CMakeLists.txt' -print0 | while IFS= read -r -d '' f; do
        sed -i.bak -E 's/(COMPONENTS[[:space:]]+Interpreter[[:space:]]+Development)\)/\1.Module)/g' "$f"
    done
    # PythonN::Python -> PythonN::Module  (extension modules must not link libpython)
    find "${PYDIR}" -name '*.cmake' -o -name 'CMakeLists.txt' | while IFS= read -r f; do
        sed -i.bak -E 's/Python3::Python/Python3::Module/g; s/Python2::Python/Python2::Module/g; s/Python::Python/Python::Module/g' "$f"
    done
    find "${PYDIR}" -name '*.bak' -delete
    echo "Patched Imath python CMake under ${PYDIR}"
else
    echo "WARNING: ${PYDIR} not found; Imath layout may have changed" >&2
fi

echo "== wheel_deps_prepare: done =="
