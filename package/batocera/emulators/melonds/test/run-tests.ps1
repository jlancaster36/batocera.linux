# Builds the MelonDS test image and runs a few smoke checks that do not
# require a ROM or a display. This is the fast validation loop for configgen
# and native emulator changes.
# Usage: pwsh package/batocera/emulators/melonds/test/run-tests.ps1
$ErrorActionPreference = "Stop"
$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "melonds-test:latest"

docker build -f (Join-Path $PSScriptRoot "Dockerfile") -t $image $pkgDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

function Assert-ExitCode($name, $expected, $actualExitCode) {
    if ($actualExitCode -ne $expected) {
        throw "$name failed: expected exit code $expected, got $actualExitCode"
    }
    Write-Host "PASS: $name"
}

$xdgRuntime = "/tmp/runtime-root"
$cmd = 'mkdir -p /tmp/runtime-root /userdata/system/configs/melonDS; chmod 700 /tmp/runtime-root; /usr/local/bin/melonDS --platform offscreen --help >/tmp/melonds-help.log 2>&1; rc=$?; cat /tmp/melonds-help.log 2>/dev/null; exit $rc'

docker run --rm `
    -e QT_QPA_PLATFORM=offscreen `
    -e XDG_RUNTIME_DIR=$xdgRuntime `
    --entrypoint /bin/bash $image -lc $cmd | Out-Null
$code = $LASTEXITCODE
Assert-ExitCode "headless help output" 0 $code

Write-Host "All MelonDS smoke tests passed."
