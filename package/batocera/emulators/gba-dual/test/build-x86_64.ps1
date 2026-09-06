# Builds gba-dual for x86_64 (Batocera on a PC) using the same Dockerfile as
# build-aarch64.ps1. Unlike aarch64, this needs no QEMU emulation - a Windows
# Docker Desktop host is already x86_64, so this is a fast native build - then
# packages the binary with its non-baseline runtime shared libraries (mgba)
# into a self-contained tarball you can SCP to the device and run directly -
# no full Batocera image rebuild, no touching the live install's system config
# yet. This is step 1 (does it even run on the real x86_64 hardware); full
# EmulationStation/configgen integration is a separate, later step (see
# custom.sh for that, unchanged from the aarch64 workflow).
# Usage: pwsh package/batocera/emulators/gba-dual/test/build-x86_64.ps1
$ErrorActionPreference = "Stop"

$pkgDir = Split-Path -Parent $PSScriptRoot
$image = "gba-dual-test:x86_64"

docker buildx build --platform linux/amd64 -f (Join-Path $PSScriptRoot "Dockerfile") -t $image --load $pkgDir
if ($LASTEXITCODE -ne 0) { throw "x86_64 build failed" }

$outDir = Join-Path $PSScriptRoot "out\x86_64-bundle"
Remove-Item -Recurse -ErrorAction SilentlyContinue $outDir
New-Item -ItemType Directory -Force -Path "$outDir\lib" | Out-Null

# Populate the bind-mounted host directory using native Linux shell tools
# instead of `docker cp` - dereferencing symlinks with `cp -L` needs no
# special privilege here, unlike recreating them on the Windows host, and
# this sidesteps a `docker cp` path-resolution bug seen with this image.
#
# Only bundle libmgba: it's the one dependency Batocera genuinely lacks in a
# usable form (its own copy is a libretro-only core built with MINIMAL_CORE=2,
# an incompatible stripped-down API surface). Everything else - SDL2, libpng,
# libzip, and especially libGL/libEGL/Mesa - must come from Batocera's own
# system libraries: LD_LIBRARY_PATH takes priority over the system path, so
# bundling a generic Debian-built libGL/libEGL would shadow the one already
# correctly matched to this device's actual kernel DRM driver and GPU, and
# silently break hardware-accelerated rendering entirely (confirmed: this is
# exactly what caused "Couldn't find matching render driver" on real ARM
# hardware - the same risk applies here for x86_64 GPUs).
$extractScript = @'
set -e
mkdir -p /out/lib
cp /build/gba-dual/gba-dual /out/gba-dual
ldd /build/gba-dual/gba-dual | while read -r needed _ resolved _; do
    case "$needed" in
        libmgba.so*) ;;
        *) continue ;;
    esac
    if [ -n "$resolved" ] && [ -f "$resolved" ]; then
        cp -L "$resolved" "/out/lib/$needed"
    fi
done
'@ -replace "`r`n", "`n"
$extractScript | Set-Content -NoNewline -Path (Join-Path $PSScriptRoot "extract-x86_64.sh")

docker run --rm --platform linux/amd64 -v "${outDir}:/out" -v "${PSScriptRoot}\extract-x86_64.sh:/extract.sh:ro" --entrypoint /bin/sh $image /extract.sh
if ($LASTEXITCODE -ne 0) { throw "failed to extract gba-dual binary and its libraries" }
Remove-Item -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "extract-x86_64.sh")

@'
#!/bin/sh
# Run gba-dual on the device using the bundled libraries next to this script
# instead of whatever versions (if any) are already installed system-wide.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$DIR/gba-dual" "$@"
'@ -replace "`r`n", "`n" | Set-Content -NoNewline -Path "$outDir\run.sh"

$tarball = Join-Path $PSScriptRoot "out\gba-dual-x86_64.tar.gz"
Remove-Item -ErrorAction SilentlyContinue $tarball
tar -czf $tarball -C $outDir .
if ($LASTEXITCODE -ne 0) { throw "failed to package tarball" }

Write-Host "PASS: built $tarball"
Write-Host "Copy it to the device and run, e.g.:"
Write-Host "  scp `"$tarball`" root@<device-ip>:/userdata/gba-dual-x86_64.tar.gz"
Write-Host "  ssh root@<device-ip> 'mkdir -p /userdata/gba-dual-test && tar -xzf /userdata/gba-dual-x86_64.tar.gz -C /userdata/gba-dual-test'"
Write-Host "  ssh root@<device-ip> '/userdata/gba-dual-test/run.sh --rom1 /path/to/game.gba --rom2 /path/to/game.gba --link'"
