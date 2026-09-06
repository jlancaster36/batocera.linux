#!/bin/bash
# Batocera boot hook (copy to /userdata/system/custom.sh, chmod +x) that
# reapplies the gba2players live-system integration on every boot, since
# /usr and /etc are an ephemeral RAM-backed overlay on Batocera - anything
# written there directly (as this test setup does, to avoid a full image
# rebuild) is lost on every reboot. Only /userdata persists.
#
# Run via /etc/init.d/S99userservices, which fires AFTER EmulationStation has
# already started at S31 - hence the explicit ES restart at the end so a
# freshly patched es_systems.cfg actually takes effect without a second boot.
#
# Prerequisite: /userdata/gba-dual-test/ must already contain gba-dual,
# lib/libmgba.so*, batocera-gba2p, and gbaDualGenerator.py (see
# test/build-aarch64.ps1 for producing the first two).
#
# This is a live-testing convenience only, not part of the real package - a
# proper Buildroot image build makes all of this unnecessary.
set -e

STAGE=/userdata/gba-dual-test

# Binary + shared lib + launcher
cp "$STAGE/gba-dual" /usr/bin/gba-dual
chmod +x /usr/bin/gba-dual
cp "$STAGE"/lib/libmgba.so* /usr/lib/
ldconfig 2>/dev/null || true
cp "$STAGE/batocera-gba2p" /usr/bin/batocera-gba2p
chmod +x /usr/bin/batocera-gba2p

# Python generator
mkdir -p /usr/lib/python3.12/site-packages/configgen/generators/gba_dual
touch /usr/lib/python3.12/site-packages/configgen/generators/gba_dual/__init__.py
cp "$STAGE/gbaDualGenerator.py" /usr/lib/python3.12/site-packages/configgen/generators/gba_dual/gbaDualGenerator.py

# Register in the generator map (idempotent)
IMPORTER=/usr/lib/python3.12/site-packages/configgen/generators/importer.py
if ! grep -q "'gba-dual'" "$IMPORTER"; then
    sed -i "/_GENERATOR_MAP: Final\[dict\[str, tuple\[str, str\]\]\] = {/a\\    'gba-dual': ('gba_dual.gbaDualGenerator', 'GbaDualGenerator')," "$IMPORTER"
fi

# Default emulator/core (idempotent)
DEFAULTS=/usr/share/batocera/configgen/configgen-defaults.yml
if ! grep -q "^gba2players:" "$DEFAULTS"; then
    sed -i '/^gbc:/i gba2players:\n  emulator: gba-dual\n  core:     gba-dual' "$DEFAULTS"
fi

# es_systems.cfg entry (idempotent) - shares the regular gba system's ROM
# folder so it lists the same library with the same scraped gamelist.xml
ES_SYSTEMS=/usr/share/emulationstation/es_systems.cfg
if ! grep -q "<name>gba2players</name>" "$ES_SYSTEMS"; then
    python3 - <<'PY'
path = "/usr/share/emulationstation/es_systems.cfg"
with open(path) as f:
    content = f.read()

marker = "<name>gba</name>"
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
print("es_systems.cfg patched OK")
PY
    /etc/init.d/S31emulationstation restart
fi
