@echo off
REM ============================================================================
REM  Path of Building (Qt) - safe launcher (Fusion style)
REM ----------------------------------------------------------------------------
REM  The native Windows Qt Quick Controls style REJECTS the custom `background`
REM  set on the themed TextField / TextArea / ScrollView controls in app/qml/
REM  main.qml. On every control (re)creation - and the CONFIG view's Repeater
REM  recreates its delegates in a refresh loop - Qt emits a warning and leaks a
REM  detached zero-size rectangle. That floods the console and spirals into a
REM  UI lockup on real Windows (Wine silently no-ops it, which is why the WSL
REM  agent dismissed it as cosmetic).
REM
REM  Forcing the Fusion style honours the custom `background`, so there is no
REM  warning and no leak -> no lockup. This is the same fix baked into
REM  app/src/main.cpp (QQuickStyle::setStyle, with this env var as override).
REM
REM  Use THIS launcher instead of double-clicking dist\pob-qt.exe directly.
REM ============================================================================
set QT_QUICK_CONTROLS_STYLE=Fusion

REM --- Phase 2: one-command build + install + launch (kills the deploy gap) ---
REM MSYS2 mingw64 location; override by setting MSYS64 before running.
if not defined MSYS64 set MSYS64=C:\msys64
set PATH=%MSYS64%\mingw64\bin;%PATH%
set REPO=%~dp0
cd /d "%REPO%build-win" || (echo [pob] build-win missing & exit /b 1)
echo [pob] building...
ninja || (echo [pob] BUILD FAILED & exit /b 1)
echo [pob] installing to dist...
cmake --install . --prefix "%REPO%." || (echo [pob] INSTALL FAILED & exit /b 1)
REM Force-copy the exe so dist is never stale vs build-win. cmake --install can
REM skip the copy when its install manifest is out of sync (reports "Up-to-date"
REM even after a rebuild), which leaves dist/pob-qt.exe older than build-win and
REM triggers the "STALE BINARY" warning + a blank tree (stale qml without the
REM layout fix). The forced copy guarantees dist always matches build-win.
copy /Y "%REPO%build-win\pob-qt.exe" "%REPO%dist\pob-qt.exe" >nul
cd /d "%REPO%"

start "" "%REPO%dist\pob-qt.exe"
