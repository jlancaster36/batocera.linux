# gba-dual

`gba-dual` is a native SDL2 frontend for two official mGBA core instances. It
accepts the same ROM for both players and composites the 240x160 framebuffers
as either a 480x160 horizontal layout or a 240x320 vertical layout.

## CLI

```text
gba-dual --rom1 GAME.gba --rom2 GAME.gba --layout horizontal --link
```

The Batocera integration launches it through `batocera-gba2p`, which reads the
`gba_dual_layout` and `gba_dual_link` system options.

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
