# Builds stock/unmodified melonDS at the pinned upstream tag and confirms the
# upstream project still builds cleanly. This is the baseline regression check.
# Usage: pwsh package/batocera/emulators/melonds/test/run-baseline.ps1
$ErrorActionPreference = "Stop"
$image = "melonds-baseline-test:latest"

docker build -f (Join-Path $PSScriptRoot "baseline.Dockerfile") -t $image $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "baseline failed: melonDS did not build cleanly at the pinned version" }

Write-Host "Baseline passed: upstream melonDS builds successfully at the pinned tag."
