#!/usr/bin/env bash
#
# cibuildwheel "before-build" step (runs ONCE per Python version).
#
# Builds Boost.Python and Imath/PyImath as SHARED libraries against the exact
# CPython that cibuildwheel is about to build the wheel with, installing them
# into a fixed prefix (DEPS_DIR). Because the prefix is fixed, the environment
# variables in pyproject.toml (BOOST_ROOT / CMAKE_PREFIX_PATH / ...) stay
# constant across Python versions; we wipe DEPS_DIR each time.
#
# CRITICAL: Boost.Python and PyImath MUST be shared. See cmake/PyAlembicWheel.cmake.
#
# Env (from pyproject.toml + cibuildwheel):
#   DEPS_DIR    install prefix (constant per OS)
#   DEPS_SRC    unpacked sources from wheel_deps_prepare.sh
set -euo pipefail

DEPS_DIR="${DEPS_DIR:?DEPS_DIR must be set}"
DEPS_SRC="${DEPS_SRC:?DEPS_SRC must be set}"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
    Darwin)               IS_MACOS=1 ;;
esac

# Skip the whole build if a complete prefix was restored from the CI cache.
if [ -f "${DEPS_DIR}/.complete" ]; then
    echo "== wheel_deps_build: cached deps at ${DEPS_DIR}, skipping build =="
    exit 0
fi

echo "== wheel_deps_build: fresh prefix ${DEPS_DIR} =="
# Clear the prefix CONTENTS (not the directory itself: on Linux it is a bind
# mount, and removing the mount point fails with "device busy"). This wipes any
# partial leftovers before a fresh build.
mkdir -p "${DEPS_DIR}"
rm -rf "${DEPS_DIR:?}"/* "${DEPS_DIR:?}"/.[!.]* 2>/dev/null || true

# --- discover the target interpreter ----------------------------------------
# cibuildwheel puts the target python first on PATH.
PY_EXE="$(python -c 'import sys; print(sys.executable)')"
PY_INCLUDE="$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')"
PY_VER="$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
echo "Target Python ${PY_VER}: ${PY_EXE}"
echo "  include: ${PY_INCLUDE}"

# ============================================================================
# 1. Boost.Python (shared)
# ============================================================================
cd "${DEPS_SRC}/boost"

if [[ "${IS_WINDOWS:-0}" == "1" ]]; then
    # On Windows b2 links pythonXY.lib, which lives in the *base* interpreter's
    # "libs" dir, not in cibuildwheel's venv. Point b2 there explicitly via the
    # 4th "libraries" field of the python rule, or linking fails (LNK1181).
    PY_LIBDIR="$(python -c 'import sys, os; print(os.path.join(sys.base_prefix, "libs"))')"
    PY_EXE_NATIVE="$(cygpath -w "${PY_EXE}" 2>/dev/null || echo "${PY_EXE}")"
    PY_INCLUDE_NATIVE="$(cygpath -w "${PY_INCLUDE}" 2>/dev/null || echo "${PY_INCLUDE}")"
    PY_LIBDIR_NATIVE="$(cygpath -w "${PY_LIBDIR}" 2>/dev/null || echo "${PY_LIBDIR}")"
    cat > user-config.jam <<EOF
using python : ${PY_VER} : "${PY_EXE_NATIVE//\\/\\\\}" : "${PY_INCLUDE_NATIVE//\\/\\\\}" : "${PY_LIBDIR_NATIVE//\\/\\\\}" ;
EOF
    ./b2 --user-config=user-config.jam --with-python \
        toolset=msvc address-model=64 \
        link=shared runtime-link=shared variant=release \
        --prefix="$(cygpath -w "${DEPS_DIR}")" install
else
    # POSIX: deliberately omit the python lib dir so libboost_python keeps
    # Python symbols UNDEFINED (required for manylinux; libpython is resolved
    # at import time by the interpreter). macOS needs undefined-dynamic-lookup.
    cat > user-config.jam <<EOF
using python : ${PY_VER} : ${PY_EXE} : ${PY_INCLUDE} ;
EOF
    EXTRA=()
    if [[ "${IS_MACOS:-0}" == "1" ]]; then
        # Pin the arch to the runner's native arch. GitHub's arm64 (macos-14)
        # runners otherwise let the toolchain default to x86_64, producing a
        # wheel whose binaries fail delocate's --require-archs arm64 check.
        MAC_ARCH="$(uname -m)"
        EXTRA+=(cflags="-arch ${MAC_ARCH}" cxxflags="-arch ${MAC_ARCH}" linkflags="-arch ${MAC_ARCH} -undefined dynamic_lookup")
    fi
    ./b2 --user-config=user-config.jam --with-python \
        link=shared variant=release "${EXTRA[@]}" \
        --prefix="${DEPS_DIR}" install
fi
echo "Boost.Python installed."

# ============================================================================
# 2. Imath + PyImath (shared)
# ============================================================================
cd "${DEPS_SRC}/imath"
rm -rf build
IMATH_EXTRA=()
if [[ "${IS_MACOS:-0}" == "1" ]]; then
    # Match Boost/alembic: force the native arch (see note above).
    IMATH_EXTRA+=("-DCMAKE_OSX_ARCHITECTURES=$(uname -m)")
fi
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DPYTHON=ON \
    -DImath_USE_PYTHON2=OFF \
    -DPython3_EXECUTABLE="${PY_EXE}" \
    -DBoost_ROOT="${DEPS_DIR}" \
    -DCMAKE_PREFIX_PATH="${DEPS_DIR}" \
    -DPYIMATH_OVERRIDE_PYTHON_INSTALL_DIR="${DEPS_DIR}/sitepkg" \
    -DCMAKE_INSTALL_PREFIX="${DEPS_DIR}" \
    "${IMATH_EXTRA[@]}"
cmake --build build --config Release --parallel
cmake --install build --config Release
echo "Imath + PyImath installed."

# --- sanity: the imath extension module must exist for bundling -------------
if ! ls "${DEPS_DIR}/sitepkg"/imath.* >/dev/null 2>&1; then
    echo "ERROR: imath extension not found in ${DEPS_DIR}/sitepkg" >&2
    ls -la "${DEPS_DIR}/sitepkg" || true
    exit 1
fi

# Mark the prefix complete so the CI cache can be reused and the prepare/build
# steps skipped on the next run. Written last so a partial build is never cached.
touch "${DEPS_DIR}/.complete"
echo "== wheel_deps_build: done =="
