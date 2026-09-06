from __future__ import annotations

from types import SimpleNamespace

import toml

from configgen.config import SystemConfig
from configgen.generators.melonds import melondsGenerator
from configgen.generators.melonds.melondsGenerator import _apply_dual_screen_layout


def test_main_display_horizontal_layout_keeps_both_windows_on_primary_display() -> None:
    config = SystemConfig({
        'emulator': 'melonds',
        'core': 'melonds',
        'melonds_dual_screen': True,
        'melonds_dual_screen_mode': 'main',
        'melonds_dual_screen_layout': 2,
    })
    base = {
        'Instance0': {
            'Window0': {'ScreenRotation': 0},
            'Window1': {'Enabled': False},
        }
    }

    _apply_dual_screen_layout(config, base)

    assert base['Instance0']['Window0']['DisplayIndex'] == 0
    assert base['Instance0']['Window1']['DisplayIndex'] == 0
    assert base['Instance0']['Window0']['ScreenLayout'] == 2
    assert base['Instance0']['Window1']['ScreenLayout'] == 2
    # main mode composites both screens inside Window0; Window1 must stay closed
    # or it becomes a second full-screen window stacked on top of Window0.
    assert base['Instance0']['Window1']['Enabled'] is False


def test_secondary_display_mode_moves_bottom_screen_to_output_2() -> None:
    config = SystemConfig({
        'emulator': 'melonds',
        'core': 'melonds',
        'melonds_dual_screen': True,
        'melonds_dual_screen_mode': 'secondary',
    })
    base = {
        'Instance0': {
            'Window0': {'ScreenRotation': 0},
            'Window1': {'Enabled': False},
        }
    }

    _apply_dual_screen_layout(config, base)

    assert base['Instance0']['Window0']['DisplayIndex'] == 0
    assert base['Instance0']['Window1']['DisplayIndex'] == 1
    assert base['Instance0']['Window1']['Enabled'] is True


def test_generate_writes_secondary_display_assignment_to_toml(tmp_path, monkeypatch) -> None:
    config_dir = tmp_path / 'configs' / 'melonDS'
    config_dir.mkdir(parents=True)
    monkeypatch.setattr(melondsGenerator, '_MELONDS_CONFIG', config_dir)

    system = SimpleNamespace(
        config=SystemConfig({
            'emulator': 'melonds',
            'core': 'melonds',
            'melonds_dual_screen': True,
            'melonds_dual_screen_mode': 'secondary',
            'melonds_dual_screen_layout': 2,
        }),
        rom=None,
    )

    generator = melondsGenerator.MelonDSGenerator()
    generator.generate(
        system=system,
        rom='/tmp/test.nds',
        playersControllers=[],
        metadata={},
        guns={},
        wheels={},
        gameResolution=None,
    )

    config = toml.load(config_dir / 'melonDS.toml')
    assert config['Instance0']['Window0']['DisplayIndex'] == 0
    assert config['Instance0']['Window1']['DisplayIndex'] == 1
    assert config['Instance0']['Window1']['Enabled'] is True
