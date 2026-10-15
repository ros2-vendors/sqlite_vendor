cmake_minimum_required(VERSION 3.7)

project(sqlite_vendor C)

find_package(ament_cmake REQUIRED)

# SQLite3 C library vendor for ROS 2 on VxWorks.
#
# rosbag2_storage_sqlite3 does find_package(SQLite3 REQUIRED) + links SQLite::SQLite3.
# The raspberrypi4b SDK ships no SQLite3 C library/header in its sysroot (only the
# Python sqlite3 module), so this vendor builds it from the upstream amalgamation.
#
# Version 3.46.1 matches Ubuntu 26.04 (resolute) libsqlite3-0 / sqlite3 (3.46.1).
# 3.46.1 predates SQLite's autosetup switch (3.49), so sqlite-autoconf-3460100 uses
# the classic GNU autoconf ./configure — hence the hand-rolled ExternalProject route
# (ament_vendor expects a git + CMake upstream; see DEPENDENCY_RESOLUTION.md §2b).
#
# The VxWorks source patches travel in ./patches and are DELIVERED BY THE LAYER
# (patches/sqlite_vendor/usr_src/0001-add-vxworks-patches.patch), not committed here.
# They are applied on top of the fetched upstream by the ExternalProject PATCH_COMMAND.

option(FORCE_BUILD_VENDOR_PKG "Build SQLite3 from source even if a system copy exists" OFF)

if(NOT FORCE_BUILD_VENDOR_PKG)
  find_package(SQLite3 QUIET)
endif()

macro(build_sqlite)
  include(ExternalProject)

  find_program(PATCH_EXECUTABLE patch REQUIRED)

  # Collect the layer-delivered VxWorks patches and chain them into a PATCH_COMMAND.
  if(NOT DEFINED SQLITE_VENDOR_PATCH_DIR)
    set(SQLITE_VENDOR_PATCH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/patches")
  endif()
  file(GLOB _sqlite_patches "${SQLITE_VENDOR_PATCH_DIR}/*.patch")
  list(SORT _sqlite_patches)
  if(NOT _sqlite_patches)
    message(FATAL_ERROR
      "sqlite_vendor: no patches in ${SQLITE_VENDOR_PATCH_DIR}. The VxWorks source "
      "patches are delivered by the layer (patches/sqlite_vendor/usr_src/*.patch).")
  endif()
  set(_patch_cmd "")
  foreach(_p IN LISTS _sqlite_patches)
    if(_patch_cmd STREQUAL "")
      set(_patch_cmd ${PATCH_EXECUTABLE} -p1 -i ${_p})
    else()
      list(APPEND _patch_cmd COMMAND ${PATCH_EXECUTABLE} -p1 -i ${_p})
    endif()
  endforeach()

  set(_prefix "${CMAKE_CURRENT_BINARY_DIR}/sqlite_install")

  # Cross-build settings. The VxWorks toolchain file sets CMAKE_C_COMPILER=wr-cc,
  # CMAKE_SYSTEM_PROCESSOR=<arch>, CMAKE_SYSROOT=$WIND_CC_SYSROOT. Mirror how the SDK
  # cross-compiles autotools 3PP (ref: $WIND_CC_SYSROOT/usr/mk/autotools.mk):
  #   --build=x86_64-pc-linux-gnu --host=<arch>-wrs-vxworks, CC=wr-cc,
  #   CONFIG_SITE=<sysroot>/usr/mk/config.site (the VxWorks autoconf feature cache that
  #   answers configure's cross probes), VxWorks 3PP warning flags.
  if(CMAKE_CROSSCOMPILING)
    set(_host_triple "${CMAKE_SYSTEM_PROCESSOR}-wrs-vxworks")
    set(_config_site "$ENV{WIND_CC_SYSROOT}/usr/mk/config.site")
  else()
    set(_host_triple "")
    set(_config_site "")
  endif()
  set(_sqlite_cflags "-fwarning-level-low -Wno-gnu-include-next -DOS_VXWORKS=1 -DSQLITE_HOMEGROWN_RECURSIVE_MUTEX=1 -DSQLITE_OMIT_LOAD_EXTENSION=1")

  # Build shared (BUILD_SHARED_LIBS=ON on VxWorks).
  externalproject_add(sqlite_external
    URL https://www.sqlite.org/2024/sqlite-autoconf-3460100.tar.gz
    URL_HASH MD5=bde7df8c2a4bce82dbf42f7e4dda0e21
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    TIMEOUT 600
    PATCH_COMMAND ${_patch_cmd}
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env
        $<$<BOOL:${_config_site}>:CONFIG_SITE=${_config_site}>
        <SOURCE_DIR>/configure
        --prefix=${_prefix}
        --build=x86_64-pc-linux-gnu
        $<$<BOOL:${CMAKE_CROSSCOMPILING}>:--host=${_host_triple}>
        --disable-static
        --disable-readline
        CC=${CMAKE_C_COMPILER}
        "CFLAGS=${_sqlite_cflags}"
    BUILD_COMMAND make -j libsqlite3.la
    INSTALL_COMMAND make install-libLTLIBRARIES install-includeHEADERS install-pkgconfigDATA
    BUILD_IN_SOURCE 0
  )

  # Stage libsqlite3.* + sqlite3.h + the generated pkgconfig into the shared prefix.
  install(
    DIRECTORY ${_prefix}/
    DESTINATION ${CMAKE_INSTALL_PREFIX}
    USE_SOURCE_PERMISSIONS
  )
endmacro()

if(NOT SQLite3_FOUND)
  message(STATUS "sqlite_vendor: SQLite3 not found, building 3.46.1 (Ubuntu 26.04) from source")
  message(STATUS "sqlite_vendor: applying VxWorks patches from ${SQLITE_VENDOR_PATCH_DIR}")
  build_sqlite()
endif()

# Export a SQLite3 config so downstream find_package(SQLite3) + SQLite::SQLite3 resolve.
ament_package(CONFIG_EXTRAS "sqlite_vendor-extras.cmake")
