# melonds - dual-screen (secondary touch display) support

This package builds [melonDS](https://github.com/melonDS-emu/melonDS) with
Batocera's existing patch stack (`001`-`004`) plus one new patch (`005`) that
adds the ability to route the DS's bottom screen to a second physical
display, so a Batocera cabinet with two monitors (e.g. a main screen plus a
small secondary touchscreen) can use the second screen as a dedicated DS
touch panel instead of squeezing both screens onto one display.

## What's new

- Two new emulator options (`melonds.emulator.yml`):
  - `melonds_dual_screen_mode`: `main` (default - both screens combined in
    one window on the primary display via melonDS's own `ScreenLayout`) or
    `secondary` (bottom screen opens as its own window, routed to the second
    physical display).
  - `melonds_dual_screen_layout`: the `ScreenLayout` value applied in dual
    screen mode (original/vertical/horizontal/hybrid), same options as
    melonDS's normal `SCREEN LAYOUT` setting.
- `_apply_dual_screen_layout()` in `melondsGenerator.py` writes the
  resulting `DisplayIndex`/`ScreenLayout`/`Enabled` values into
  `Instance0.Window0`/`Window1` in the generated `melonDS.toml`.
- `005-display-index-placement.patch` makes melonDS's `Window.cpp`
  constructor actually honor a `DisplayIndex` config value before it resizes
  the window - see "Why a new patch was needed" below.

## Why a new patch was needed

Writing a `DisplayIndex` key into melonDS's TOML config does **nothing** on
its own - neither vanilla upstream melonDS nor Batocera's own existing
`001`-`004` patches ever read such a key anywhere in the window-creation
code. Batocera's `002-fix-fullscreen.patch` unconditionally forces **every**
window (including a second one, if enabled) onto
`QGuiApplication::primaryScreen()`'s geometry right before `show()` - that's
the actual code that was pinning the bottom screen to the main display
regardless of any config value. `005-display-index-placement.patch` changes
that exact block to pick the target `QScreen` from `DisplayIndex` (falling
back to the primary screen if unset), then `move()`s the window there before
resizing.

`Window1` (the second window) must stay disabled (`Enabled = false`) in
`main` mode - it is a genuinely separate top-level window in melonDS, not
something that auto-composites into `Window0`. Enabling it in `main` mode
would open a second full-screen window stacked directly on top of the first
one.

## Known issues / not yet done

- **Production binary not yet cross-compiled via the real Buildroot
  toolchain.** The binary validated during live-device testing was built via
  the Docker test harness (Debian bookworm), which is fine for confirming
  the patch/config logic but is not the ABI-safe artifact that should ship -
  a full image build (or a proper aarch64/x86_64 cross-build per the
  `emulator-test-workflow` skill) is required before merging for real.
- **`batocera-backglass` conflicts with the second display.** It renders a
  marquee window on the secondary output and is only torn down on
  `game-selected`/`system-selected` ES events (its `game-start`/`game-end`
  hooks are commented out upstream), so it blocks melonDS's second window
  entirely unless disabled first (`batocera-backglass disable`). A real fix
  would add proper `game-start`/`game-end` hooks to that package so it
  coexists with any dual-display emulator, not just melonDS.
- **Touchscreens are not auto-calibrated.** A touch panel's default X11
  `Coordinate Transformation Matrix` spans the whole virtual desktop, not
  just its own monitor, and even after mapping it to the right output
  (`xinput map-to-output`) the auto-computed matrix can still be measurably
  offset in practice - a real per-device calibration (via `evtest`'s
  reported `ABS_X`/`ABS_Y` range and two physical reference touches) may be
  needed. This is host/hardware setup, not something this package can fix
  generically.
- Keyboard input is not configured by Batocera's controller-mapping
  pipeline (`melondsGenerator.py` only ever writes gamepad/joystick
  bindings) - a real gamepad is required for testing; keyboard-only input
  needs manual binding inside melonDS's own Input/hotkeys dialog.

## Live-device validation

Validated end-to-end on a real x86_64 SBC with a small secondary touch
display attached (HDMI-1 1920x1080 primary + DP-1 1024x600 secondary,
extended desktop):

- `main` mode: both screens render combined on the primary display,
  unchanged from stock behavior.
- `secondary` mode: top screen stays on the primary display, bottom screen
  opens on the secondary display and correctly receives touch input once
  the touch panel is calibrated.
- Gamepad input confirmed working; touch input confirmed working after
  per-device X11 calibration (see "Known issues" above).

See `test/custom.sh` for the boot-hook pattern used to live-patch a running
Batocera device (binary, generator, `es_features.cfg`, and the touchscreen
mapping) without a full image rebuild, per the repo's
`emulator-test-workflow` skill.
