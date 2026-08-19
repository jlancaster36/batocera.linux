from __future__ import annotations

from typing import TYPE_CHECKING

from ... import Command
from ...controller import Controller, generate_sdl_game_controller_config
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
        commandArray = ["/usr/bin/batocera-gba2p", rom]

        # Same convention as cemuGenerator: SDL_GAMECONTROLLERCONFIG makes SDL
        # (and therefore gba-dual, which is a plain SDL2 app) interpret each
        # physical pad using the exact mapping the user configured in ES,
        # rather than SDL's built-in guess for that GUID.
        player1 = Controller.find_player_number(playersControllers, 1)
        player2 = Controller.find_player_number(playersControllers, 2)
        if player1 is not None:
            commandArray += ["--controller1", str(player1.index)]
        if player2 is not None:
            commandArray += ["--controller2", str(player2.index)]

        return Command.Command(
            array=commandArray,
            env={
                "gba_dual_layout": system.config.get("gba_dual_layout", "horizontal"),
                "gba_dual_link": system.config.get("gba_dual_link", "true"),
                "SDL_GAMECONTROLLERCONFIG": generate_sdl_game_controller_config(playersControllers),
            },
        )

    def getInGameRatio(self, config, gameResolution, rom):
        return 3 / 2 if config.get("gba_dual_layout", "horizontal") == "horizontal" else 3 / 4
