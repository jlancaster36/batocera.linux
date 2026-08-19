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
- Audio mixing is not yet connected to the SDL audio callback.
- The mGBA GBA lockstep coordinator and link-port drivers still need to be
  attached before link-cable games can be considered supported.

The package deliberately stages the official mGBA library and headers so the
frontend uses the real `mCore` API rather than an invented wrapper API.
