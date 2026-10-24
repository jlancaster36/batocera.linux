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
if [ -f "$DEFAULTS" ] && ! grep -A1 "^nds:" "$DEFAULTS" | grep -q "emulator: melonds"; then
    if grep -q "^nds:" "$DEFAULTS"; then
        python3 - "$DEFAULTS" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"^nds:\n  emulator: \S+\n  core:\s*\S+", "nds:\n  emulator: melonds\n  core:     melonds", s, flags=re.M)
open(p, "w").write(s)
PY
    else
        sed -i '/^nes:/i nds:\n  emulator: melonds\n  core:     melonds' "$DEFAULTS"
    fi
fi

# Dual-screen-display feature entry (idempotent) - /usr is an ephemeral
# overlay, so this must be reapplied on every boot, not just once.
FEATURES=/usr/share/emulationstation/es_features.cfg
if [ -f "$FEATURES" ] && ! grep -q "melonds_dual_screen_mode" "$FEATURES"; then
    sed -i '/<feature name="DUAL SCREEN" value="melonds_dual_screen"/i\
    <feature name="DUAL SCREEN DISPLAY" value="melonds_dual_screen_mode" description="Keep both DS screens on the main display or move the bottom screen to the secondary display.">\
      <choice name="Main display (both screens)" value="main"/>\
      <choice name="Secondary display (bottom screen)" value="secondary"/>\
    </feature>\
    <feature name="DUAL SCREEN LAYOUT" value="melonds_dual_screen_layout" description="Select how the two DS screens are laid out when dual-screen mode is enabled.">\
      <choice name="Original screen positions" value="0"/>\
      <choice name="Vertical stack" value="1"/>\
      <choice name="Horizontal split" value="2"/>\
      <choice name="Hybrid" value="3"/>\
    </feature>' "$FEATURES"
fi

# Ensure dual MST display layout is established if MST outputs DP-3 and DP-4 are active
if command -v xrandr >/dev/null 2>&1; then
    DISPLAY=:0 xrandr --output DP-3 --primary --mode 1920x1080 --pos 0x0 --output DP-4 --mode 1920x1080 --pos 1920x0 2>/dev/null || true
fi

# Map the touchscreen to the secondary output (DP-4 on MST / DP-1 on direct).
# Dynamically resolves the touch device by name/identifier (UCTRONICS/QinHeng,
# WaveShare, or QDtech) to guard against device ID shifts across reboots.
if command -v xinput >/dev/null 2>&1; then
    TARGET_OUT=$(DISPLAY=:0 xrandr 2>/dev/null | grep -E "^(DP-4|DP-1) connected" | awk '{print $1}' | head -n1)
    TARGET_OUT=${TARGET_OUT:-DP-4}
    TOUCH_ID=$(DISPLAY=:0 xinput list 2>/dev/null | grep -iE "USB2IIC|WaveShare|QDtech|MPI" | grep -o "id=[0-9]*" | cut -d= -f2 | head -n1)
    if [ -n "$TOUCH_ID" ]; then
        DISPLAY=:0 xinput map-to-output "$TOUCH_ID" "$TARGET_OUT" 2>/dev/null || true
    fi
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
