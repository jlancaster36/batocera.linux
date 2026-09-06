# Builds the gba-dual test image and runs a few smoke checks that don't
# require a real ROM or a display (the failure paths run before SDL_Init).
# Usage: pwsh package/batocera/emulators/gba-dual/test/run-tests.ps1
$ErrorActionPreference = "Stop"
$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "gba-dual-test:latest"

docker build -f (Join-Path $PSScriptRoot "Dockerfile") -t $image $pkgDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

function Assert-ExitCode($name, $expected, $actualExitCode) {
    if ($actualExitCode -ne $expected) {
        throw "$name failed: expected exit code $expected, got $actualExitCode"
    }
    Write-Host "PASS: $name"
}

docker run --rm --entrypoint /build/gba-dual/gba-dual $image | Out-Null
Assert-ExitCode "usage with no args" 1 $LASTEXITCODE

docker run --rm --entrypoint /bin/sh $image -c "echo not-a-rom > /tmp/rom.gba && /build/gba-dual/gba-dual --rom1 /tmp/rom.gba --rom2 /tmp/rom.gba" | Out-Null
Assert-ExitCode "invalid rom rejected" 1 $LASTEXITCODE

Write-Host "All gba-dual smoke tests passed."
