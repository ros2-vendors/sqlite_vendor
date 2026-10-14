# sqlite_vendor-extras.cmake
#
# Loaded by downstream packages via find_package(sqlite_vendor). SQLite3 is resolved
# by CMake's bundled FindSQLite3 module (sqlite3.h + libsqlite3), which this vendor
# installed into the shared install prefix. Make sure that prefix is on the search
# path so a cross build (CMAKE_FIND_ROOT_PATH_MODE_* = ONLY in the VxWorks toolchain)
# can locate them.
#
# Consumers (e.g. rosbag2_storage_sqlite3) then do find_package(SQLite3 REQUIRED) and
# link SQLite::SQLite3 as usual.

if(NOT "${CMAKE_INSTALL_PREFIX}" IN_LIST CMAKE_FIND_ROOT_PATH)
  list(APPEND CMAKE_FIND_ROOT_PATH "${CMAKE_INSTALL_PREFIX}")
endif()
