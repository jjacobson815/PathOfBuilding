# Runs at `cmake --install` time (see app/CMakeLists.txt install(SCRIPT ...)).
#
# The repo-root manifest.xml has a <Version number="..."/> with NO branch/platform
# attributes. Launch.lua (OnInit) treats such a manifest as "remote-style" and
# enables devMode, which routes the user-data path into the SOURCE TREE instead of
# Documents/Path of Building — silently defeating the GetUserPath fix for every
# installed user (Part 0.3). Stamp branch+platform onto the packaged copy so the
# installed app is NOT detected as a source checkout, and drop an installed.cfg
# marker. Dev builds (run from the build tree) still read the un-stamped repo
# manifest and keep devMode, which is the correct isolation for developers.
#
# Fails safe: if the regex ever fails to match, an un-stamped manifest simply won't
# parse as remote-style with branch/platform — but a malformed manifest still yields
# devMode=false (no version parsed), so userPath stays on Documents either way.

if(NOT DEFINED POB_MANIFEST_SRC)
    message(WARNING "pack-manifest: POB_MANIFEST_SRC not set; skipping manifest stamp")
    return()
endif()

file(READ "${POB_MANIFEST_SRC}" _man)
if(NOT _man MATCHES "branch=")
    string(REGEX REPLACE
        "(<Version number=\"[^\"]*\")[ \t]*/>"
        "\\1 branch=\"release\" platform=\"win32\" />"
        _man "${_man}")
endif()
file(WRITE "${CMAKE_INSTALL_PREFIX}/dist/manifest.xml" "${_man}")
file(WRITE "${CMAKE_INSTALL_PREFIX}/dist/src/installed.cfg" "qt\n")
message(STATUS "pack-manifest: wrote branch/platform-stamped manifest + installed.cfg to dist/")
