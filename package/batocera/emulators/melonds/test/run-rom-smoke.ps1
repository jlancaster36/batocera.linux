# Runs melonDS against a real ROM you provide without a display, using an
# offscreen Qt backend. This is the practical no-window smoke test for the
# second display path while still validating the ROM loads and starts.
# Usage: pwsh package/batocera/emulators/melonds/test/run-rom-smoke.ps1 -Rom "C:\path\to\game.nds"
param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [int]$Seconds = 15
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Rom)) {
    throw "ROM not found: $Rom"
}

$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "melonds-test:latest"
$romFull = (Resolve-Path -LiteralPath $Rom).Path
$xdgRuntime = "/tmp/runtime-root"
$cmd = "mkdir -p /tmp/runtime-root /userdata/system/configs/melonDS; chmod 700 /tmp/runtime-root; timeout -k 3s ${Seconds}s /usr/local/bin/melonDS --platform offscreen /rom.nds >/tmp/melonds-rom.log 2>&1; rc=$?; cat /tmp/melonds-rom.log 2>/dev/null; exit $rc"

docker build -f (Join-Path $PSScriptRoot "Dockerfile") -t $image $pkgDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

docker run --rm `
    -e QT_QPA_PLATFORM=offscreen `
    -e XDG_RUNTIME_DIR=$xdgRuntime `
    -v "${romFull}:/rom.nds:ro" `
    --entrypoint /bin/bash $image -lc $cmd | Out-Null
$code = $LASTEXITCODE
if ($code -notin 0, 124, 137) { throw "melonDS failed to start the ROM (exit $code)" }

Write-Host "PASS: melonDS launched a real ROM headlessly (exit $code, timeout reached as expected)"
