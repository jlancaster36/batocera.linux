# Builds and packages Azahar for aarch64 via Docker buildx.
$ErrorActionPreference = "Stop"

$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "azahar-test:aarch64"

Write-Host "Starting aarch64 build of Azahar..."
docker buildx build --platform linux/arm64 -f (Join-Path $PSScriptRoot "Dockerfile") -t $image --load $pkgDir
if ($LASTEXITCODE -ne 0) { throw "aarch64 build failed" }

$outDir = Join-Path $PSScriptRoot "out\aarch64-bundle"
Remove-Item -Recurse -ErrorAction SilentlyContinue $outDir
New-Item -ItemType Directory -Force -Path "$outDir\bin" | Out-Null

$extractScript = @'
set -e
mkdir -p /out/bin
cp /usr/local/bin/azahar /out/bin/azahar
'@ -replace "`r`n", "`n"
$extractScript | Set-Content -NoNewline -Path (Join-Path $PSScriptRoot "extract-aarch64.sh")

docker run --rm --platform linux/arm64 -v "${outDir}:/out" -v "${PSScriptRoot}\extract-aarch64.sh:/extract.sh:ro" --entrypoint /bin/sh $image /extract.sh
if ($LASTEXITCODE -ne 0) { throw "failed to extract azahar binary" }
Remove-Item -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "extract-aarch64.sh")

$tarball = Join-Path $PSScriptRoot "out\azahar-aarch64.tar.gz"
Remove-Item -ErrorAction SilentlyContinue $tarball
tar -czf $tarball -C $outDir .
if ($LASTEXITCODE -ne 0) { throw "failed to package tarball" }

Write-Host "PASS: built $tarball"
