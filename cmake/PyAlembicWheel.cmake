#-******************************************************************************
# Wheel-only packaging extras for PyAlembic (fork addition).
#
# When building a wheel via scikit-build-core, the prebuilt PyImath "imath"
# extension module is bundled into the wheel next to the alembic module.
#
# IMPORTANT: Boost.Python and PyImath must be SHARED libraries. PyImath
# registers its type converters into Boost.Python's global converter
# registry (which lives inside libboost_python), and the alembic module
# imports "imath" at init time. Both extensions must resolve to the same
# shared libboost_python/libPyImath copies, or type conversion between the
# modules breaks. Never static-link Boost.Python or PyImath in wheel builds.
#
# This file is a no-op outside scikit-build-core wheel builds.
#-******************************************************************************

if (DEFINED SKBUILD AND DEFINED PYALEMBIC_BUNDLE_IMATH_DIR AND NOT PYALEMBIC_BUNDLE_IMATH_DIR STREQUAL "")
    file(GLOB PYIMATH_EXT_MODULES "${PYALEMBIC_BUNDLE_IMATH_DIR}/imath.*")
    if (NOT PYIMATH_EXT_MODULES)
        message(FATAL_ERROR "No imath extension found in ${PYALEMBIC_BUNDLE_IMATH_DIR}")
    endif()
    message(STATUS "Bundling PyImath extension(s) into wheel: ${PYIMATH_EXT_MODULES}")
    install(FILES ${PYIMATH_EXT_MODULES} DESTINATION ${ALEMBIC_PYTHON_INSTALL_DIR})
endif()
