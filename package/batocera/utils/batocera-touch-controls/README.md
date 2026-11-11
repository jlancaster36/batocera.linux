# Touch controls for MAME 2003 Plus

This cabinet-side prototype displays a spinner or trackball on the secondary
Sway output while a matching MAME 2003 Plus game runs. It reads the core's
`mame2003-plus.xml.gz` metadata and uses its `dial` and `trackball` classifications.
Some dial games have steering wheels or rotary joysticks. Other emulators and
cores are not affected.

The touchscreen is reserved for the panel during the game and released on exit.
Gamepad mappings are unchanged. The panel refuses to start if a mouse or
touchpad is already attached, rather than changing the existing player-one
mouse selection. It currently requires exactly one touchscreen, two active
Sway outputs configured with `global.videooutput` and `global.videooutput2`,
and an unrotated secondary output. It requires Python, pygame, evdev, pyudev,
and `/dev/uinput`. Errors are recorded in
`/userdata/system/logs/touch-controls.log` or the launcher log.

## Installation

Copy `detect.py`, `motion.py`, `panel.py`, and `hook.py` into
`/userdata/system/touch-controls/`. Install `touch-controls` as an executable
at `/userdata/system/scripts/touch-controls`. These paths are in the persistent
userdata partition. Do not replace an existing hook or directory with the same
name without checking its contents. The hook must retain Unix (LF) line endings.

To disable the mod, remove the `touch-controls` hook from the scripts directory
after exiting the game. Existing backglass content should reappear when the
panel closes. Sensitivity and touch orientation should be checked on the actual
cabinet before relying on the controls.
