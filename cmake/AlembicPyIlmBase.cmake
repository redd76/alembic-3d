##-*****************************************************************************
##
## Copyright (c) 2009-2016,
##  Sony Pictures Imageworks Inc. and
##  Industrial Light & Magic, a division of Lucasfilm Entertainment Company Ltd.
##
## All rights reserved.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are
## met:
## *       Redistributions of source code must retain the above copyright
## notice, this list of conditions and the following disclaimer.
## *       Redistributions in binary form must reproduce the above
## copyright notice, this list of conditions and the following disclaimer
## in the documentation and/or other materials provided with the
## distribution.
## *       Neither the name of Industrial Light & Magic nor the names of
## its contributors may be used to endorse or promote products derived
## from this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
## "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
## LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
## A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
## OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
## SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
## LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
## DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
## THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
## (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
## OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##
##-*****************************************************************************

# Locate PyImath, which Alembic links against for the Python bindings.
#
# Imath exposes PyImath inconsistently across versions/build configs:
#   * Some installs export an imported target Imath::PyImath (COMPONENTS path).
#   * Older 3.0/3.1 exported Imath::PyImath_Python<maj>_<min>.
#   * A from-source Imath 3.1 build installs the shared library
#     (libPyImath_Python<maj>_<min>-<Imath maj>_<min>.{so,dylib,lib}) but does
#     NOT export any PyImath CMake target at all.
# Try the imported targets first, then fall back to locating the library file.
FIND_PACKAGE(Imath COMPONENTS PyImath)
IF (Imath_FOUND AND TARGET Imath::PyImath)
    SET(ALEMBIC_PYIMATH_LIB Imath::PyImath)
ELSE()
    FIND_PACKAGE(Imath REQUIRED)
    SET(_pyimath_suffix Python${Python_VERSION_MAJOR}_${Python_VERSION_MINOR})
    IF (TARGET Imath::PyImath)
        SET(ALEMBIC_PYIMATH_LIB Imath::PyImath)
    ELSEIF (TARGET Imath::PyImath_${_pyimath_suffix})
        SET(ALEMBIC_PYIMATH_LIB Imath::PyImath_${_pyimath_suffix})
    ELSE()
        # No exported target: find the installed library directly. Names cover
        # the version-suffixed soname (PyImath_Python3_12-3_1) as well as
        # unsuffixed variants.
        FIND_LIBRARY(ALEMBIC_PYIMATH_LIBRARY
            NAMES
                PyImath_${_pyimath_suffix}-${Imath_VERSION_MAJOR}_${Imath_VERSION_MINOR}
                PyImath_${_pyimath_suffix}
                PyImath-${Imath_VERSION_MAJOR}_${Imath_VERSION_MINOR}
                PyImath
        )
        IF (NOT ALEMBIC_PYIMATH_LIBRARY)
            MESSAGE(FATAL_ERROR "Could not find a PyImath target or library from Imath")
        ENDIF()
        SET(ALEMBIC_PYIMATH_LIB ${ALEMBIC_PYIMATH_LIBRARY})
        # A bare library path carries no include dirs; PyImath*.h live in
        # Imath's include dir, so propagate it from the Imath::Imath target.
        GET_TARGET_PROPERTY(_imath_incs Imath::Imath INTERFACE_INCLUDE_DIRECTORIES)
        IF (_imath_incs)
            INCLUDE_DIRECTORIES(${_imath_incs})
        ENDIF()
    ENDIF()
    MESSAGE(STATUS "Found package Imath using PyImath: ${ALEMBIC_PYIMATH_LIB}")
ENDIF()
