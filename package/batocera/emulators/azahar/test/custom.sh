#!/bin/bash
# Batocera combined boot hook for live-testing:
#   1. gba2players (gba-dual)
#   2. MelonDS dual-display
#   3. Azahar 3DS dual-display (Sway rules + binary staging)
# All live-patch the ephemeral /usr and /etc overlays on boot.
set -e

# ==========================================
# 1. GBA-DUAL (gba2players)
# ==========================================
GBA_STAGE=/userdata/gba-dual-test

if [ -f "$GBA_STAGE/gba-dual" ]; then
    cp "$GBA_STAGE/gba-dual" /usr/bin/gba-dual
    chmod +x /usr/bin/gba-dual
    cp "$GBA_STAGE"/lib/libmgba.so* /usr/lib/ 2>/dev/null || true
    ldconfig 2>/dev/null || true
    cp "$GBA_STAGE/batocera-gba2p" /usr/bin/batocera-gba2p 2>/dev/null || true
    chmod +x /usr/bin/batocera-gba2p 2>/dev/null || true

    mkdir -p /usr/lib/python3.12/site-packages/configgen/generators/gba_dual
    touch /usr/lib/python3.12/site-packages/configgen/generators/gba_dual/__init__.py
    if [ -f "$GBA_STAGE/gbaDualGenerator.py" ]; then
        cp "$GBA_STAGE/gbaDualGenerator.py" /usr/lib/python3.12/site-packages/configgen/generators/gba_dual/gbaDualGenerator.py
    fi

    IMPORTER=/usr/lib/python3.12/site-packages/configgen/generators/importer.py
    if [ -f "$IMPORTER" ] && ! grep -q "'gba-dual'" "$IMPORTER"; then
        sed -i "/_GENERATOR_MAP: Final\[dict\[str, tuple\[str, str\]\]\] = {/a\\    'gba-dual': ('gba_dual.gbaDualGenerator', 'GbaDualGenerator')," "$IMPORTER"
    fi

    DEFAULTS=/usr/share/batocera/configgen/configgen-defaults.yml
    if [ -f "$DEFAULTS" ] && ! grep -q "^gba2players:" "$DEFAULTS"; then
        sed -i '/^gbc:/i gba2players:\n  emulator: gba-dual\n  core:     gba-dual' "$DEFAULTS"
    fi

    # Add gba2players system to EmulationStation
    ES_SYSTEMS=/usr/share/emulationstation/es_systems.cfg
    if [ -f "$ES_SYSTEMS" ] && ! grep -q "<name>gba2players</name>" "$ES_SYSTEMS"; then
        python3 - <<'PY'
path = "/usr/share/emulationstation/es_systems.cfg"
with open(path) as f:
    content = f.read()

marker = "<name>gba</name>"
if marker in content:
    idx = content.index(marker)
    end_idx = content.index("</system>", idx) + len("</system>")

    new_block = """
  <system>
        <fullname>Game Boy Advance (2 Players)</fullname>
        <name>gba2players</name>
        <manufacturer>Nintendo</manufacturer>
        <release>2001</release>
        <hardware>portable</hardware>
        <path>/userdata/roms/gba</path>
        <extension>.gba</extension>
        <command>emulatorlauncher %CONTROLLERSCONFIG% -system %SYSTEM% -rom %ROM% -gameinfoxml %GAMEINFOXML% -systemname %SYSTEMNAME%</command>
        <platform>gba</platform>
        <theme>gba</theme>
        <emulators>
            <emulator name="gba-dual">
                <cores>
                    <core default="true">gba-dual</core>
                </cores>
            </emulator>
        </emulators>
  </system>"""
    content = content[:end_idx] + new_block + content[end_idx:]
    with open(path, "w") as f:
        f.write(content)
print("es_systems.cfg patched for gba2players OK")
PY
    fi

    # Add gba-dual features to es_features.cfg
    FEATURES=/usr/share/emulationstation/es_features.cfg
    if [ -f "$FEATURES" ] && ! grep -q 'name="gba-dual"' "$FEATURES"; then
        python3 - <<'PY'
feat_path = "/usr/share/emulationstation/es_features.cfg"
with open(feat_path, "r") as f:
    f_content = f.read()

if 'name="gba-dual"' not in f_content:
    closing_tag = "</features>"
    c_idx = f_content.rfind(closing_tag)
    features_block = """  <emulator name="gba-dual" features="padtokeyboard">
    <systems>
      <system name="gba2players" features="padtokeyboard" >
        <sharedFeature value="powermode" />
        <sharedFeature value="tdp" />
        <sharedFeature value="videomode" />
        <sharedFeature value="bezel" />
        <feature name="SPLIT LAYOUT" value="gba_dual_layout" description="Arrange the two GBA screens horizontally or vertically.">
          <choice name="Horizontal (Default)" value="horizontal" />
          <choice name="Vertical" value="vertical" />
        </feature>
        <feature name="LINK CABLE" value="gba_dual_link" description="Enable the mGBA GBA multiplayer link backend.">
          <choice name="Enabled (Default)" value="true" />
          <choice name="Disabled" value="false" />
        </feature>
        <feature name="2P AUDIO PANNING" value="gba_dual_audio_pan" description="Spatial stereo audio separation for 2-player split screen.">
          <choice name="Stereo Blend (Default)" value="blend" />
          <choice name="Hard Split (L/R)" value="split" />
          <choice name="Centered (Equal)" value="center" />
        </feature>
      </system>
    </systems>
  </emulator>
"""
    f_content = f_content[:c_idx] + features_block + f_content[c_idx:]
    with open(feat_path, "w") as f:
        f.write(f_content)
    print("es_features.cfg patched for gba-dual OK")
PY
    fi
fi

# ==========================================
# 2. MELONDS DUAL-SCREEN
# ==========================================
MELON_STAGE=/userdata/melonds-test

if [ -f "$MELON_STAGE/bin/melonDS" ]; then
    cp "$MELON_STAGE/bin/melonDS" /usr/bin/melonDS
    chmod +x /usr/bin/melonDS
fi

mkdir -p /usr/lib/python3.12/site-packages/configgen/generators/melonds
if [ -f "$MELON_STAGE/melondsGenerator.py" ]; then
    cp "$MELON_STAGE/melondsGenerator.py" /usr/lib/python3.12/site-packages/configgen/generators/melonds/melondsGenerator.py
fi

IMPORTER=/usr/lib/python3.12/site-packages/configgen/generators/importer.py
if [ -f "$IMPORTER" ] && ! grep -q "'melonds'" "$IMPORTER"; then
    sed -i "/_GENERATOR_MAP: Final\[dict\[str, tuple\[str, str\]\]\] = {/a\\    'melonds': ('melonds.melondsGenerator', 'MelonDSGenerator')," "$IMPORTER"
fi

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

FEATURES=/usr/share/emulationstation/es_features.cfg
if [ -f "$FEATURES" ] && ! grep -q "melonds_dual_screen_layout" "$FEATURES"; then
    sed -i '/<feature name="CONSOLE TYPE" value="melonds_console"/i\
    <feature name="DUAL SCREEN LAYOUT" value="melonds_dual_screen_layout" description="Select how the two DS screens are laid out when dual-screen mode is enabled.">\
      <choice name="Original screen positions" value="0"/>\
      <choice name="Vertical stack" value="1"/>\
      <choice name="Horizontal split" value="2"/>\
      <choice name="Hybrid" value="3"/>\
    </feature>' "$FEATURES"
fi
if [ -f "$FEATURES" ] && ! grep -q "melonds_dual_screen_mode" "$FEATURES"; then
    sed -i '/<feature name="CONSOLE TYPE" value="melonds_console"/i\
    <feature name="DUAL SCREEN DISPLAY" value="melonds_dual_screen_mode" description="Keep both DS screens on the main display or move the bottom screen to the secondary display.">\
      <choice name="Main display (both screens)" value="main"/>\
      <choice name="Secondary display (bottom screen)" value="secondary"/>\
    </feature>' "$FEATURES"
fi
if [ -f "$FEATURES" ] && ! grep -q 'value="melonds_dual_screen"' "$FEATURES"; then
    sed -i '/<feature name="CONSOLE TYPE" value="melonds_console"/i\
    <feature name="DUAL SCREEN" value="melonds_dual_screen" description="Enable MelonDS to display over two screens. Some related screen options will be ignored.">\
      <choice name="Off" value="False"/>\
      <choice name="On" value="True"/>\
    </feature>' "$FEATURES"
fi

# ==========================================
# 3. AZAHAR 3DS DUAL-SCREEN
# ==========================================
AZAHAR_STAGE=/userdata/azahar-test

if [ -f "$AZAHAR_STAGE/bin/azahar" ]; then
    cp "$AZAHAR_STAGE/bin/azahar" /usr/bin/azahar
    chmod +x /usr/bin/azahar
fi

if [ -f "$AZAHAR_STAGE/libs.tar.gz" ]; then
    tar -xzf "$AZAHAR_STAGE/libs.tar.gz" -C /usr/lib/ 2>/dev/null || true
    ldconfig 2>/dev/null || true
fi

# Deploy clean generator and create wayland socket symlink in XDG_RUNTIME_DIR
mkdir -p /usr/lib/python3.12/site-packages/configgen/generators/azahar
if [ -f "$AZAHAR_STAGE/azaharGenerator.py" ]; then
    cp "$AZAHAR_STAGE/azaharGenerator.py" /usr/lib/python3.12/site-packages/configgen/generators/azahar/azaharGenerator.py
fi
mkdir -p /userdata/saves/3ds/azahar-emu /userdata/saves/3ds/azaharplus-emu
ln -sf /var/run/wayland-1 /userdata/saves/3ds/azahar-emu/wayland-1 2>/dev/null || true
ln -sf /var/run/wayland-1 /userdata/saves/3ds/azaharplus-emu/wayland-1 2>/dev/null || true
mkdir -p /userdata/system/configs
ln -sfn /userdata/system/.config/azahar-emu /userdata/system/configs/azahar-emu 2>/dev/null || true
ln -sfn /userdata/system/.config/azahar-emu /userdata/system/configs/azaharplus-emu 2>/dev/null || true

ES_SYSTEMS=/usr/share/emulationstation/es_systems.cfg
# Ensure 3ds is in es_systems.cfg pointing to azahar
if [ -f "$ES_SYSTEMS" ] && ! grep -q "<name>3ds</name>" "$ES_SYSTEMS"; then
    python3 - <<'PY'
path = "/usr/share/emulationstation/es_systems.cfg"
with open(path) as f:
    content = f.read()

new_block = """
  <system>
        <fullname>Nintendo 3DS</fullname>
        <name>3ds</name>
        <manufacturer>Nintendo</manufacturer>
        <release>2011</release>
        <hardware>portable</hardware>
        <path>/userdata/roms/3ds</path>
        <extension>.3ds .3dsx .cxi .cxe .app .7z .zip</extension>
        <command>emulatorlauncher %CONTROLLERSCONFIG% -system %SYSTEM% -rom %ROM% -gameinfoxml %GAMEINFOXML% -systemname %SYSTEMNAME%</command>
        <platform>3ds</platform>
        <theme>3ds</theme>
        <emulators>
            <emulator name="azahar">
                <cores>
                    <core default="true">azahar</core>
                </cores>
            </emulator>
        </emulators>
  </system>"""

c_idx = content.rfind("</systemList>")
if c_idx != -1:
    content = content[:c_idx] + new_block + "\n" + content[c_idx:]
    with open(path, "w") as f:
        f.write(content)
    print("es_systems.cfg patched for 3ds OK")
PY
fi

# Ensure azahar dual-screen layout feature is in es_features.cfg
FEATURES=/usr/share/emulationstation/es_features.cfg
if [ -f "$FEATURES" ] && ! grep -q "azahar_screen_layout" "$FEATURES"; then
    python3 - <<'PY'
feat_path = "/usr/share/emulationstation/es_features.cfg"
with open(feat_path, "r") as f:
    f_content = f.read()

if 'azahar_screen_layout' not in f_content:
    closing_tag = "</features>"
    c_idx = f_content.rfind(closing_tag)
    azahar_block = """  <emulator name="azahar" features="">
    <feature name="SCREEN LAYOUT" value="azahar_screen_layout" description="Arrange the dual screen layout. Separate windows can be changed with Hotkey+R2.">
      <choice name="Default" value="0-false"/>
      <choice name="Top Only" value="1-false"/>
      <choice name="Bottom Only" value="1-true"/>
      <choice name="Large Top" value="2-false"/>
      <choice name="Large Bottom" value="2-true"/>
      <choice name="Left/Right" value="3-false"/>
      <choice name="Right/Left" value="3-true"/>
      <choice name="Separate Windows (Dual Screen)" value="4-false"/>
      <choice name="Hybrid Screen Top" value="5-false"/>
      <choice name="Hybrid Screen Bottom" value="5-true"/>
    </feature>
  </emulator>
"""
    f_content = f_content[:c_idx] + azahar_block + f_content[c_idx:]
    with open(feat_path, "w") as f:
        f.write(f_content)
    print("es_features.cfg patched for azahar OK")
PY
fi

# Sway rules for Azahar dual-window routing
# On this cabinet: DP-1 is the 1920x1080 main display; HDMI-A-1 is the 1024x600 touchscreen.
SWAY_CONF=/etc/sway/config
if [ -f "$SWAY_CONF" ]; then
    sed -i '/Azahar 3DS dual-screen window routing/,/for_window.*Azahar/d' "$SWAY_CONF" 2>/dev/null || true
    cat >> "$SWAY_CONF" <<'SWAY_EOF'

# Azahar 3DS dual-screen window routing
workspace 1 output DP-1
workspace 2 output HDMI-A-1
for_window [app_id=org.azahar_emu.Azahar] move to workspace 1, fullscreen enable
for_window [app_id=org.azahar_emu.Azahar title=.*Secondary.*] move to workspace 2, fullscreen enable
SWAY_EOF
fi

# ==========================================
# 4. INPUT / DISPLAY SHARED TWEAKS
# ==========================================
# Enable secondary display in Sway if second video output is configured
if command -v swaymsg >/dev/null 2>&1; then
    sec_out=$(batocera-settings-get global.videooutput2 2>/dev/null || echo "")
    if [ -n "$sec_out" ]; then
        swaymsg "output $sec_out enable" 2>/dev/null || true
        swaymsg "output $sec_out pos 1920 0" 2>/dev/null || true
    fi
    # Map WaveShare touchscreen to secondary display HDMI-A-1
    swaymsg input "3823:5:WaveShare_WS170120" map_to_output HDMI-A-1 2>/dev/null || true

    # Install game start/end hook to manage dual displays and focus
    mkdir -p /userdata/system/scripts
    cat > /userdata/system/scripts/game-end <<'GE_EOF'
#!/bin/sh
ACTION=$1
SYSTEM=$2

if command -v swaymsg >/dev/null 2>&1; then
    export SWAYSOCK=$(ls /var/run/sway-ipc.*.sock 2>/dev/null | head -n 1)
    if [ "$ACTION" = "gameStart" ]; then
        sec_out=$(batocera-settings-get global.videooutput2 2>/dev/null || echo "")
        if [ -n "$sec_out" ]; then
            swaymsg "output $sec_out enable" 2>/dev/null || true
            swaymsg "output $sec_out pos 1920 0" 2>/dev/null || true
        fi
        swaymsg input "3823:5:WaveShare_WS170120" map_to_output HDMI-A-1 2>/dev/null || true

        # For 3ds / Azahar: poll briefly to ensure secondary window is moved to HDMI-A-1 and fullscreened
        if [ "$SYSTEM" = "3ds" ]; then
            (
                for i in $(seq 1 15); do
                    sleep 0.5
                    swaymsg "[app_id=org.azahar_emu.Azahar title=.*Secondary.*] move to workspace 2" 2>/dev/null || true
                    swaymsg "[app_id=org.azahar_emu.Azahar title=.*Secondary.*] fullscreen enable" 2>/dev/null || true
                    swaymsg "[app_id=org.azahar_emu.Azahar] fullscreen enable" 2>/dev/null || true
                done
            ) &
        fi
    elif [ "$ACTION" = "gameStop" ]; then
        swaymsg focus output DP-1 2>/dev/null || true
    fi
fi
GE_EOF
    chmod +x /userdata/system/scripts/game-end
fi

# Touchscreen mapping for X11 setups (WaveShare WS170120 calibrated matrix)
if command -v xinput >/dev/null 2>&1; then
    XORG_SOCKET=$(ls /tmp/.X11-unix/ 2>/dev/null | head -1)
    if [ -n "$XORG_SOCKET" ]; then
        XORG_DISPLAY=":${XORG_SOCKET#X}"
        DISPLAY="$XORG_DISPLAY" XAUTHORITY=/var/lib/.Xauthority \
            xinput set-prop "WaveShare WS170120" "Coordinate Transformation Matrix" \
            0.374514 0 0.645615 0 0.563190 -0.002751 0 0 1 2>/dev/null || true
    fi
fi

# Disable backglass if running so it doesn't block second display
if command -v batocera-backglass >/dev/null 2>&1; then
    batocera-backglass disable >/dev/null 2>&1 || true
fi

# ==========================================
# 5. RESTART EMULATIONSTATION
# ==========================================
if [ -x /etc/init.d/S31emulationstation ]; then
    /etc/init.d/S31emulationstation restart || true
fi
