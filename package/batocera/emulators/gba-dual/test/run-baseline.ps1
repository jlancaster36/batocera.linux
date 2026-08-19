# Builds stock/unmodified mGBA at the pinned commit and runs its own unit test
# suite. This is the regression baseline: if this ever fails, the problem is
# upstream mGBA (or the pin), not gba-dual. Run this before run-tests.ps1 when
# bumping LIBRETRO_MGBA_VERSION or investigating an unexplained failure.
# Usage: pwsh package/batocera/emulators/gba-dual/test/run-baseline.ps1
$ErrorActionPreference = "Stop"
$image = "mgba-baseline-test:latest"

docker build -f (Join-Path $PSScriptRoot "baseline.Dockerfile") -t $image $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "baseline failed: pinned mGBA commit did not build or its unit tests did not pass" }

Write-Host "Baseline passed: pinned mGBA commit builds and its own unit test suite is green."
