# gba-dual

`gba-dual` is a native SDL2 frontend for two official mGBA core instances. It
accepts the same ROM for both players and composites the 240x160 framebuffers
as either a 480x160 horizontal layout or a 240x320 vertical layout.

## CLI

```text
gba-dual --rom1 GAME.gba --rom2 GAME.gba --layout horizontal --link [--bezel PATH]
```

The Batocera integration launches it through `batocera-gba2p`, which reads the
`gba_dual_layout` and `gba_dual_link` system options, plus resolves and passes
`--bezel` when a decoration set is selected for the `gba2players` system (see
"Custom bezel support" below).

## Current implementation status

- Two mGBA cores are loaded in one process.
- SDL2 presentation and controller routing are implemented.
- Horizontal and vertical compositing are implemented, letterboxed/
  pillarboxed to preserve each layout's native aspect ratio instead of
  stretching to fill the window (important under compositors that force
  fullscreen, e.g. sway on Batocera).
- Real GBA link-cable sync (`--link`, the default) runs both cores on their
  own `mCoreThread` with a shared `GBASIOLockstepCoordinator`, matching mgba's
  own Qt frontend architecture. Verified against Mario Kart Super Circuit's
  **Multi Pak** link mode. **Single Pak** mode (BIOS multiboot, for a second
  console with no cartridge) is not applicable here since both instances
  always load a full ROM, and is not implemented.
- `--no-link` and the `--frames`/`--screenshot` headless test mode still use
  the simpler single-thread synchronous loop (no real link timing).
- Audio from both instances is mixed and sent to a single SDL audio device
  (per-instance `mAudioResampler`, summed and clamped to 16-bit). Works for
  both `--link` and `--no-link`.
- Custom bezel support (horizontal layout only): `gba-dual` composites its own
  bezel artwork internally rather than relying on Batocera's external
  `batocera-bezel-overlay` process, which isn't installed on every image and
  whose cover-ratio validation assumes a 4:3 game area, incorrectly rejecting
  a genuinely wide dual-screen layout. `GbaDualGenerator.supportsInternalBezels()`
  returns `True` to skip that path entirely; the generator resolves the active
  decoration set via the same `bezelsUtil.getBezelInfos()` Batocera itself
  uses, and passes the PNG path via `--bezel`. `load_bezel()` in `main.c` loads
  the image with mGBA's own `mImageLoad`, then auto-detects each player's
  "screen window" by scanning the alpha channel for the transparent bounding
  box on each side of the image's horizontal midpoint - no separate `.info`/
  `.lay` metadata file is required, the cutouts are inferred directly from the
  artwork. `render()` draws the composited GBA frame into those two cutouts
  (scaled to the window/output size), then draws the bezel texture on top with
  alpha blending. Vertical layout bezels aren't supported yet and fall back to
  the plain letterboxed rendering.
- Controller input: each player's SDL_GameController buttons are opened via
  `--controller1`/`--controller2` (SDL joystick indices, supplied by
  `gbaDualGenerator.py` from Batocera's real per-player controller pairing).
  Face buttons follow the same convention as every other RetroArch/mgba GBA
  setup - the physical bottom button (SDL `A`) maps to GBA **B**, the
  physical right button (SDL `B`) maps to GBA **A** - since real GBA hardware
  puts A on the right and B below-left, the opposite of Xbox-style labeling.
  The left analog stick is also mapped to the D-pad (OR'd with the digital
  D-pad so either can be used), with a deadzone to ignore analog noise. At
  startup, `gba-dual` also loads any of Batocera's bundled community
  `gamecontrollerdb.txt` files (moonlight/ppsspp/sdl-jstest/amiberry) as a
  mapping fallback, so pads not in SDL's own compiled-in database (e.g.
  generic DragonRise USB adapters) still register as game controllers.
- Validated on real hardware (Orange Pi 5 / RK3588, Batocera on sway +
  Xwayland): video, audio, real link-cable sync, and controller input
  (including the analog stick D-pad) all confirmed working end-to-end,
  launched through EmulationStation.

The package deliberately stages the official mGBA library and headers so the
frontend uses the real `mCore` API rather than an invented wrapper API.

## EmulationStation / configgen integration

`gba2players` is a real Batocera system (`es_systems.yml`), grouped with and
sharing the regular `gba` system's ROM folder (`path: gba`) so it lists the
same library with the same scraped `gamelist.xml`/box art, with no separate
scraping step - both systems just launch the same `.gba` files through
different emulators (`libretro`/`mgba` for single player, `gba-dual` for
split-screen). The original single-player `gba` system is untouched, so both
remain independently launchable; 2-player mode only ever runs when launched
from the `gba2players` system, since they're fully separate ES entries.

Three pieces have to agree for a native (non-libretro) emulator like this to
be launchable from ES - all are provided by this package:

- `configs/configgen-defaults.yml` (in `batocera-configgen`) sets the actual
  runtime default `emulator: gba-dual` / `core: gba-dual` for the
  `gba2players` system name. This - not `es_systems.cfg` - is what
  `configgen`'s `Emulator.py` reads to decide what to launch; a system
  missing from this file raises `MissingEmulator` ("Error: Emulator
  missing" in the ES UI) even if `es_systems.cfg` and the binary are fine.
- `generators/importer.py`'s `_GENERATOR_MAP` maps the `gba-dual` emulator
  name (a hyphen, so it can't use the default bare-module-name convention)
  to `gba_dual.gbaDualGenerator.GbaDualGenerator`.
- `generators/gba_dual/gbaDualGenerator.py` builds the actual command line
  and env vars (`--controller1`/`--controller2`, `SDL_GAMECONTROLLERCONFIG`,
  `gba_dual_layout`, `gba_dual_link`) from ES's real per-player controller
  pairing, the same way `cemuGenerator.py` does.

When testing any of this by hand-patching an already-installed Batocera image
(rather than a full image rebuild), keep in mind `/usr` and `/etc` are an
ephemeral RAM-backed overlay over a read-only base (`overlay` mount with
`lowerdir=/overlay_root/base,upperdir=/overlay_root/overlay`) - live changes
there are automatically undone by a reboot, which makes this kind of manual
verification low-risk. `/userdata` is the only persistent part.

## Local test environment

The full Batocera Buildroot toolchain is too slow for an edit/compile loop, so
`test/` has four Docker-based tiers, all run from PowerShell:

- `test/run-baseline.ps1` — builds the exact pinned mGBA commit completely
  unmodified and runs mGBA's own cmocka unit test suite. No gba-dual code is
  involved. Run this first, and again after bumping the pin, to confirm any
  failure is not caused by upstream mGBA itself.
- `test/run-tests.ps1` — builds gba-dual against that same pinned commit and
  runs smoke tests that don't need a ROM or a display.
- `test/run-rom-smoke.ps1 -Rom "C:\path\to\game.gba"` — runs gba-dual
  headlessly (`--frames`/`--screenshot`, no window or X server needed) against
  a real ROM **you supply** and saves a BMP screenshot so you can see it
  actually decode and render the game. Your ROM is only bind-mounted at
  container runtime; it is never copied into the Docker image (see
  `.dockerignore`) and never added to git. The screenshot in `test/out/` is
  git-ignored for the same copyright reason - don't commit ROMs or renders of
  copyrighted games.
- `test/run-audio-smoke.ps1 -Rom "C:\path\to\game.gba"` — runs the
  interactive `--link` session for a few seconds with SDL's `disk` audio
  driver (writes raw PCM to a file instead of a speaker) and asserts the
  capture isn't silence. This exists because gba-dual once ran cleanly,
  crash-free, with a fully wired audio pipeline that produced 100% silence
  (`core->opts.volume` defaulted to 0) - a bug no crash-based test could
  catch. Same ROM handling as run-rom-smoke.ps1: bind-mounted only, never
  committed.

Run the baseline before the other tiers when diagnosing a new failure.

## aarch64 real-hardware builds

`test/build-aarch64.ps1` cross-compiles gba-dual for aarch64 via Docker's
QEMU-based `buildx`, and packages `gba-dual` + `libmgba.so*` (only) plus a
`run.sh` wrapper into `test/out/gba-dual-aarch64.tar.gz`. Only `libmgba` is
bundled - SDL2, libpng, libzip, and especially libGL/libEGL/Mesa must come
from the target device's own system libraries, since `LD_LIBRARY_PATH` takes
priority over the system path and a generic Debian-built GL/EGL/Mesa would
shadow the one already correctly matched to the device's actual kernel DRM
driver and GPU (confirmed: this is exactly what caused a "Couldn't find
matching render driver" failure on real hardware). Copy the resulting tarball
to the device (e.g. `scp` to `/userdata`) and extract/run it to smoke-test on
real ARM64 hardware before a full EmulationStation integration test.

## Testing the ES integration on an already-installed Batocera device

For iterating on the EmulationStation/configgen integration without a full
Buildroot image rebuild, you can hand-patch a live device directly (see
"EmulationStation / configgen integration" above for exactly what needs to
change: `configgen-defaults.yml`, `importer.py`'s `_GENERATOR_MAP`,
`es_systems.cfg`, plus installing the binary/lib/launcher/generator to their
real system paths). This works because `/usr` and `/etc` are writable at
runtime, but **it does not persist**: Batocera's root filesystem is an
ephemeral, RAM-backed overlay (`overlay` mount with
`lowerdir=/overlay_root/base,upperdir=/overlay_root/overlay`) - only
`/userdata` survives a reboot, so all of this is lost the next time the
device restarts.

`test/custom.sh` is a copy-to-`/userdata/system/custom.sh` boot hook (a real,
Batocera-supported mechanism - see `/etc/init.d/S99userservices`) that
reapplies the whole live install automatically on every boot, reading its
binary/lib/launcher/generator inputs from a persistent staging directory
(`/userdata/gba-dual-test/`, produced by `build-aarch64.ps1` plus a couple of
extra files - see the comment at the top of `test/custom.sh`). It's
idempotent (checks before patching each file) and restarts EmulationStation
itself at the end, since `S99userservices` runs after `S31emulationstation`
has already started. This is a live-testing convenience only, not part of
the real package - a proper image build makes it unnecessary.

## TODOs

### Per-player save data and save states

- Add independent save storage for each player in the two-player mode.
- Default behavior should be: player 1 and player 2 each get their own save
  file, RTC state, and save-state storage so games like Pokémon Emerald can
  continue from different progress on the same ROM without overwriting one
  another.
- Recommended layout in `/userdata`:
  - `/userdata/saves/gba2players/<game-id>/player1/`
  - `/userdata/saves/gba2players/<game-id>/player2/`
  - optional `/userdata/saves/gba2players/<game-id>/shared/` only for
    explicitly link-shared games.
- Keep the single-player `gba` system's existing save behavior unchanged.

### Vertical layout bezel support

- `load_bezel()` currently only auto-detects screen cutouts by splitting the
  artwork at its horizontal midpoint, so bezels are only composited when
  `gba_dual_layout` is `horizontal`. A vertical-layout bezel would need the
  same detection split top/bottom instead, plus test artwork to verify against.

### Per-game bezel overrides

- Batocera's decoration convention supports per-ROM bezel overrides (see
  `bezelsUtil.getBezelInfos()`'s game/system/default lookup order) and
  `GbaDualGenerator.generate()` already resolves through that same lookup, so
  a `games/<romname>.png` in the active decoration pack should already work -
  this just hasn't been tested against a real per-game override yet.

## Known issues

- **Intermittent on real hardware, `--link` mode, not yet root-caused**: the
  first `--link` launch through EmulationStation after a fresh device boot
  has been observed once with one screen stuck (not advancing) and framerate
  around 18fps instead of the usual ~60fps, followed by a segfault during
  process teardown (after the SDL_QUIT path had already started, per the
  trace log - not during the steady-state render loop). Immediately retrying
  the identical launch worked normally with no code changes, which points to
  a genuine timing-sensitive race rather than a deterministic bug - possibly
  in `mCoreThread` startup/teardown ordering, which real ARM hardware
  (weaker memory ordering, RK3588's mixed Cortex-A76/A55 scheduling) can
  expose in ways x86 Docker testing does not. Needs a reliable repro (e.g.
  launching/quitting in a loop) before it can be debugged further.
