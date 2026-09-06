# Builds the MelonDS binary in a native x86_64 Docker environment and packages
# the executable for deployment to a real Batocera host without a full image
# rebuild. The intent is to validate that the emulator runs on the host OS
# before doing any device-level EmulationStation or configgen integration.
# Usage: pwsh package/batocera/emulators/melonds/test/build-x86_64.ps1
$ErrorActionPreference = "Stop"

$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "melonds-test:x86_64"

docker buildx build --platform linux/amd64 -f (Join-Path $PSScriptRoot "Dockerfile") -t $image --load $pkgDir
if ($LASTEXITCODE -ne 0) { throw "x86_64 build failed" }

$outDir = Join-Path $PSScriptRoot "out\x86_64-bundle"
Remove-Item -Recurse -ErrorAction SilentlyContinue $outDir
New-Item -ItemType Directory -Force -Path "$outDir\bin" | Out-Null

$extractScript = @'
set -e
mkdir -p /out/bin
cp /usr/local/bin/melonDS /out/bin/melonDS
'@ -replace "`r`n", "`n"
$extractScript | Set-Content -NoNewline -Path (Join-Path $PSScriptRoot "extract-x86_64.sh")

docker run --rm --platform linux/amd64 -v "${outDir}:/out" -v "${PSScriptRoot}\extract-x86_64.sh:/extract.sh:ro" --entrypoint /bin/sh $image /extract.sh
if ($LASTEXITCODE -ne 0) { throw "failed to extract melonDS binary" }
Remove-Item -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "extract-x86_64.sh")

@'
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$DIR/bin/melonDS" "$@"
'@ -replace "`r`n", "`n" | Set-Content -NoNewline -Path "$outDir\run.sh"

$tarball = Join-Path $PSScriptRoot "out\melonds-x86_64.tar.gz"
Remove-Item -ErrorAction SilentlyContinue $tarball
tar -czf $tarball -C $outDir .
if ($LASTEXITCODE -ne 0) { throw "failed to package tarball" }

Write-Host "PASS: built $tarball"
Write-Host "Copy it to the device and run, e.g.:"
Write-Host "  scp `"$tarball`" root@<device-ip>:/userdata/melonds-x86_64.tar.gz"
Write-Host "  ssh root@<device-ip> 'mkdir -p /userdata/melonds-test && tar -xzf /userdata/melonds-x86_64.tar.gz -C /userdata/melonds-test'"
Write-Host "  ssh root@<device-ip> '/userdata/melonds-test/run.sh --help'"
