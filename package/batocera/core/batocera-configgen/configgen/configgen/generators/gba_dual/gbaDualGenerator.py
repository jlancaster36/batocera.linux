from __future__ import annotations

from typing import TYPE_CHECKING

from ... import Command
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext


class GbaDualGenerator(Generator):
    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "gba-dual",
            "keys": {
                "exit": ["KEY_LEFTALT", "KEY_F4"],
            },
        }

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):
        return Command.Command(
            array=["/usr/bin/batocera-gba2p", rom],
            env={
                "gba_dual_layout": system.config.get("gba_dual_layout", "horizontal"),
                "gba_dual_link": system.config.get("gba_dual_link", "true"),
            },
        )

    def getInGameRatio(self, config, gameResolution, rom):
        return 3 / 2 if config.get("gba_dual_layout", "horizontal") == "horizontal" else 3 / 4
