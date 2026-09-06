#!/bin/bash
# Batocera boot hook for live-testing the MelonDS dual-display integration without
# a full image rebuild. This copies the locally staged binary, generator, and
# config defaults into the live system paths and restarts EmulationStation so the
# new feature can be validated immediately on-device.
set -e

STAGE=/userdata/melonds-test

# Binary
if [ -f "$STAGE/bin/melonDS" ]; then
    cp "$STAGE/bin/melonDS" /usr/bin/melonDS
    chmod +x /usr/bin/melonDS
fi

# Python generator
mkdir -p /usr/lib/python3.12/site-packages/configgen/generators/melonds
if [ -f "$STAGE/melondsGenerator.py" ]; then
    cp "$STAGE/melondsGenerator.py" /usr/lib/python3.12/site-packages/configgen/generators/melonds/melondsGenerator.py
fi

# Register in the generator map (idempotent)
IMPORTER=/usr/lib/python3.12/site-packages/configgen/generators/importer.py
if [ -f "$IMPORTER" ] && ! grep -q "'melonds'" "$IMPORTER"; then
    sed -i "/_GENERATOR_MAP: Final\[dict\[str, tuple\[str, str\]\]\] = {/a\\    'melonds': ('melonds.melondsGenerator', 'MelonDSGenerator')," "$IMPORTER"
fi

# Default emulator/core (idempotent)
DEFAULTS=/usr/share/batocera/configgen/configgen-defaults.yml
if [ -f "$DEFAULTS" ] && ! grep -q "^nds:" "$DEFAULTS"; then
    sed -i '/^nes:/i nds:\n  emulator: melonds\n  core:     melonds' "$DEFAULTS"
fi

# Dual-screen-display feature entry (idempotent) - /usr is an ephemeral
# overlay, so this must be reapplied on every boot, not just once.
FEATURES=/usr/share/emulationstation/es_features.cfg
if [ -f "$FEATURES" ] && ! grep -q "melonds_dual_screen_mode" "$FEATURES"; then
    sed -i '/<feature name="DUAL SCREEN" value="melonds_dual_screen"/i\
    <feature name="DUAL SCREEN DISPLAY" value="melonds_dual_screen_mode" description="Keep both DS screens on the main display or move the bottom screen to the secondary display.">\
      <choice name="Main display (both screens)" value="main"/>\
      <choice name="Secondary display (bottom screen)" value="secondary"/>\
    </feature>' "$FEATURES"
fi

# Map the WaveShare touchscreen to the secondary output (DP-1) with a matrix
# empirically calibrated against its real reported ABS range (0-4096, per
# `evtest`), not the geometric map-to-output approximation - that guess was
# off enough to be visibly offset in-game. Note: the X input device named
# "DP-1" is NOT this touchscreen - it's an unrelated CEC remote control input
# that happens to share the output's name.
if command -v xinput >/dev/null 2>&1; then
    XORG_SOCKET=$(ls /tmp/.X11-unix/ 2>/dev/null | head -1)
    XORG_DISPLAY=":${XORG_SOCKET#X}"
    DISPLAY="$XORG_DISPLAY" XAUTHORITY=/var/lib/.Xauthority \
        xinput set-prop "WaveShare WS170120" "Coordinate Transformation Matrix" \
        0.374514 0 0.645615 0 0.563190 -0.002751 0 0 1 2>/dev/null || true
fi

# batocera-backglass permanently occupies the secondary display with its own
# marquee window and only tears down on game-selected/system-selected ES
# events (its game-start/game-end hooks are disabled upstream), so it blocks
# MelonDS's secondary-display window entirely if left running. Disable it by
# default on this test box; `|| true` since it exits 1 if already disabled.
if command -v batocera-backglass >/dev/null 2>&1; then
    batocera-backglass disable >/dev/null 2>&1 || true
fi

# Restart EmulationStation so the config changes take effect
if [ -x /etc/init.d/S31emulationstation ]; then
    /etc/init.d/S31emulationstation restart || true
fi
