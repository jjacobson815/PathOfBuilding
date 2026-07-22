# Deploy Path of Building (Qt) on Windows as a FULLY SELF-CONTAINED dist that
# double-clicks with no msys2/mingw on PATH.
#
# This is a thin wrapper around app/deploy-win-standalone.sh, which is the
# canonical, self-testing deployer. Two steps are essential on msys2 and are
# handled there but NOT by a plain `windeployqt` run:
#   * copying the full mingw dependency closure (zlib1, libgcc, libstdc++,
#     libwinpthread, ICU, lua51, ...) next to the exe, and
#   * writing qt.conf so Qt6Core (loaded from dist/) finds dist/qml instead of a
#     nonexistent ../share/qt6/qml relative to itself.
# Doing this in the bash script keeps ONE tested code path instead of two.
#
# Prerequisites:
#   * A build:  ninja -C build-win pob-qt   (or your build dir)
#   * msys2 with mingw64 Qt6 (bash + windeployqt available)
#
# Usage:
#   pwsh app/deploy.ps1                       # uses build-win/ -> dist/
#   $env:BUILD="path"; $env:DIST="path"; pwsh app/deploy.ps1   # override dirs
$ErrorActionPreference = "Stop"

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    Write-Error "bash not found. Install msys2 / git-bash, or run app/deploy-win-standalone.sh directly from an msys2 shell."
}

$script = Join-Path $PSScriptRoot "deploy-win-standalone.sh"
& $bash.Source $script
if ($LASTEXITCODE -ne 0) {
    Write-Error "Standalone deploy failed (exit $LASTEXITCODE). See output above."
}
