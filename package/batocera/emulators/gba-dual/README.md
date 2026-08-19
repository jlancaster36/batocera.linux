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
- Horizontal and vertical compositing are implemented.
- Real GBA link-cable sync (`--link`, the default) runs both cores on their
  own `mCoreThread` with a shared `GBASIOLockstepCoordinator`, matching mgba's
  own Qt frontend architecture. Verified against Mario Kart Super Circuit's
  **Multi Pak** link mode. **Single Pak** mode (BIOS multiboot, for a second
  console with no cartridge) is not applicable here since both instances
  always load a full ROM, and is not implemented.
- `--no-link` and the `--frames`/`--screenshot` headless test mode still use
  the simpler single-thread synchronous loop (no real link timing).
- Audio mixing is not yet connected to the SDL audio callback.

The package deliberately stages the official mGBA library and headers so the
frontend uses the real `mCore` API rather than an invented wrapper API.

## Local test environment

The full Batocera Buildroot toolchain is too slow for an edit/compile loop, so
`test/` has two Docker-based tiers, both run from PowerShell:

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

Run the baseline before the other tiers when diagnosing a new failure.
