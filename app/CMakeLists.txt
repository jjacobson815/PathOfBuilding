cmake_minimum_required(VERSION 3.16)
project(pob-qt VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick Svg QuickControls2)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LUAJIT REQUIRED luajit)

# --- Native dependency bridges (Phase 0d) ----------------------------------
# zlib: Inflate/Deflate import-code bridge (l_pob_inflate/l_pob_deflate).
find_package(ZLIB REQUIRED)
# libcurl: synchronous HTTP backend for the lcurl.safe shim (l_pob_http).
pkg_check_modules(CURL REQUIRED libcurl)

# --- GUI application (QML shell) -------------------------------------------
add_executable(pob-qt
    src/main.cpp
    src/LuaEngine.cpp
    src/TextMetrics.cpp
    src/Theme.cpp
    src/ColorText.cpp
    src/BuildModel.cpp
    src/SocketGroupModel.cpp
    src/BuildListModel.cpp
    src/SaveLoadModel.cpp
    src/TreeModel.cpp
    src/TreeGroupModel.cpp
    src/TreeConnectorModel.cpp
    src/TreeViewController.cpp
    src/ItemModel.cpp
    src/ItemSlotModel.cpp
    src/JewelSocketModel.cpp
    src/SkillModel.cpp
    src/CalcModel.cpp
    src/ConfigModel.cpp
    src/NotesController.cpp
    src/CompareModel.cpp
    src/PartyModel.cpp
    src/luabridge.cpp
    qml/qml.qrc
)
target_include_directories(pob-qt PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${LUAJIT_INCLUDE_DIRS}
    ${CURL_INCLUDE_DIRS}
)
target_link_libraries(pob-qt PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Svg Qt6::QuickControls2
    ${LUAJIT_LIBRARIES}
    ZLIB::ZLIB
    ${CURL_LIBRARIES}
)
target_compile_definitions(pob-qt PRIVATE
    POB_LUA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/lua"
)

# --- Headless self-test (no GUI) -------------------------------------------
# Verifies the LuaJIT bridge loads the calc engine and runs a calculation.
add_executable(pob-selftest
    src/selftest.cpp
    src/LuaEngine.cpp
    src/TextMetrics.cpp
    src/luabridge.cpp
)
target_include_directories(pob-selftest PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${LUAJIT_INCLUDE_DIRS}
    ${CURL_INCLUDE_DIRS}
)
target_link_libraries(pob-selftest PRIVATE
    Qt6::Core
    ${LUAJIT_LIBRARIES}
    ZLIB::ZLIB
    ${CURL_LIBRARIES}
)
target_compile_definitions(pob-selftest PRIVATE
    POB_LUA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/lua"
    POB_NO_GUI
)

# --- Phase 6c: self-contained distribution layout -------------------------
# `cmake --install .` produces a `dist/` folder containing the Qt app plus ONLY
# the files the Qt/QML port needs at runtime. The legacy SimpleGraphic runtime
# (SimpleGraphic.dll, Path of Building.exe, lua51.dll, Update.exe,
# runtime/SimpleGraphic/) is deliberately NOT copied — the Qt app replaces that
# engine entirely. EXCEPTION: runtime/SimpleGraphic/Fonts/ (the .tgf metrics +
# .ttf render fonts TextMetrics/Theme load, Phase 1.2a) ships regardless — it's
# data the Qt port owns now, not the legacy engine. The host bootstrap lands at
# dist/lua/pob_host.lua and the engine sources at dist/src, matching the
# exe-relative resolution in main.cpp (which also chdir's to dist/src so the
# engine's relative TreeData/ + manifest.xml paths resolve).
install(TARGETS pob-qt RUNTIME DESTINATION dist)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/lua DESTINATION dist
        FILES_MATCHING PATTERN "*.lua")
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../src DESTINATION dist)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../runtime/lua DESTINATION dist/runtime)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../runtime/SimpleGraphic/Fonts
        DESTINATION dist/runtime/SimpleGraphic)
# Native Lua C module the engine require()s at boot. src/Modules/Common.lua does
# require('lua-utf8'); pob_host.lua resolves it from _RUNTIME_DIR (dist/runtime),
# so lua-utf8.dll (+ its lua51.dll Lua-API dependency) MUST ship there. Without
# it the engine fails to load its main script, no modes/tree are built, and the
# UI comes up blank — the exact symptom of an install that copied only
# runtime/lua/. (lcurl/lzip are covered by the bundled Lua shims in app/lua, so
# only lua-utf8 needs the native DLL.) These two are NOT part of the excluded
# legacy SimpleGraphic runtime above.
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../runtime/lua-utf8.dll
              ${CMAKE_CURRENT_SOURCE_DIR}/../runtime/lua51.dll
        DESTINATION dist/runtime)
# Manifest: do NOT copy the repo-root manifest verbatim. It has a <Version> with
# no branch/platform, which Launch.lua treats as a source-checkout marker and
# enables devMode -> userPath routed into the source tree, defeating the
# Documents/Path of Building user-data fix (Part 0.3). pack-manifest.cmake stamps
# branch+platform onto the packaged copy (so the installed app is not seen as a
# checkout) and writes an installed.cfg marker into dist/src.
install(CODE "set(POB_MANIFEST_SRC \"${CMAKE_CURRENT_SOURCE_DIR}/../manifest.xml\")")
install(SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/pack-manifest.cmake)
