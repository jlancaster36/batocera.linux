# Captures real audio output using SDL's "disk" driver (writes raw PCM to a
# file instead of a speaker) and asserts it isn't silence. This exists because
# gba-dual once ran cleanly, crash-free, with a fully wired audio pipeline
# that was actually producing 100% silence (core->opts.volume defaulted to 0
# since mCoreLoadConfig() only overwrites opts fields present in the config
# file, which never has a "volume" key) - a bug that "did it crash" tests
# cannot catch. This runs the interactive --link path for a fixed wall-clock
# duration (there is no headless audio path) and inspects the captured PCM.
# Usage: pwsh package/batocera/emulators/gba-dual/test/run-audio-smoke.ps1 -Rom "C:\path\to\game.gba"
param(
    [Parameter(Mandatory = $true)][string]$Rom,
    [int]$Seconds = 8,
    [double]$MinNonZeroFraction = 0.05
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
$captureFile = Join-Path $outDir "audio-smoke.raw"
Remove-Item -ErrorAction SilentlyContinue $captureFile

$containerName = "gba-dual-audio-smoke"
docker rm -f $containerName 2>$null | Out-Null
docker run -d --name $containerName `
    -e SDL_AUDIODRIVER=disk -e SDL_DISKAUDIOFILE=/out/audio-smoke.raw `
    -v "${romFull}:/rom.gba:ro" -v "${outDir}:/out" `
    --entrypoint /build/gba-dual/gba-dual `
    $image --rom1 /rom.gba --rom2 /rom.gba --link | Out-Null
if ($LASTEXITCODE -ne 0) { throw "docker run failed to start" }

Start-Sleep -Seconds $Seconds
docker stop $containerName | Out-Null
docker rm $containerName | Out-Null

if (-not (Test-Path -LiteralPath $captureFile)) {
    throw "no audio was captured - SDL disk audio driver never wrote a file"
}

$bytes = [System.IO.File]::ReadAllBytes($captureFile)
$sampleCount = [int]($bytes.Length / 2)
if ($sampleCount -eq 0) {
    throw "captured audio file is empty"
}
$samples = New-Object 'System.Int16[]' $sampleCount
[System.Buffer]::BlockCopy($bytes, 0, $samples, 0, $bytes.Length)

$nonZero = 0
$min = [int16]::MaxValue
$max = [int16]::MinValue
for ($i = 0; $i -lt $sampleCount; $i++) {
    $s = $samples[$i]
    if ($s -ne 0) { $nonZero++ }
    if ($s -lt $min) { $min = $s }
    if ($s -gt $max) { $max = $s }
}
$fraction = $nonZero / $sampleCount

Write-Host ("Captured {0} samples, {1:P2} non-zero, range [{2}, {3}]" -f $sampleCount, $fraction, $min, $max)
if ($fraction -lt $MinNonZeroFraction) {
    throw ("FAIL: only {0:P2} of samples were non-zero (threshold {1:P0}) - audio is effectively silent" -f $fraction, $MinNonZeroFraction)
}
Write-Host "PASS: captured audio is not silent"
