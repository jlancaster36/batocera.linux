# Runs gba-dual against a real ROM you provide, headlessly (no window or X
# server needed), and saves a screenshot so you can actually see it decode and
# render the game. Your ROM is only bind-mounted at container runtime — it is
# never copied into the Docker image and never added to git. The output
# screenshot lands in test/out/, which is git-ignored for the same reason.
# Usage: pwsh package/batocera/emulators/gba-dual/test/run-rom-smoke.ps1 -Rom "C:\path\to\game.gba"
param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [int]$Frames = 180,
    [ValidateSet("horizontal", "vertical")][string]$Layout = "horizontal"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Rom)) {
    throw "ROM not found: $Rom"
}

$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "gba-dual-test:latest"

docker build -f (Join-Path $PSScriptRoot "Dockerfile") -t $image $pkgDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

$romFull = (Resolve-Path -LiteralPath $Rom).Path
$outDir = Join-Path $PSScriptRoot "out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$screenshot = Join-Path $outDir "rom-smoke.bmp"
Remove-Item -ErrorAction SilentlyContinue $screenshot

docker run --rm `
    -v "${romFull}:/rom.gba:ro" `
    -v "${outDir}:/out" `
    --entrypoint /build/gba-dual/gba-dual `
    $image --rom1 /rom.gba --rom2 /rom.gba --layout $Layout --frames $Frames --screenshot /out/rom-smoke.bmp
if ($LASTEXITCODE -ne 0) { throw "gba-dual failed to run the ROM (exit $LASTEXITCODE)" }

if (-not (Test-Path $screenshot)) { throw "screenshot was not produced" }
Write-Host "PASS: ran $Frames frames from both instances against a real ROM"
Write-Host "Screenshot: $screenshot"
