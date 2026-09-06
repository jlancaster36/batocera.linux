from __future__ import annotations

from typing import TYPE_CHECKING

from ... import Command
from ...controller import Controller, generate_sdl_game_controller_config
from ...utils import bezels as bezelsUtil
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext


class GbaDualGenerator(Generator):
    # gba-dual composites its own bezel internally (see main.c), auto-detecting
    # each player's screen cutout from the bezel PNG's transparent areas rather
    # than relying on Batocera's external batocera-bezel-overlay process and its
    # 4:3-only cover-ratio heuristics, which reject a genuinely wide dual-screen
    # layout.
    def supportsInternalBezels(self) -> bool:
        return True

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

        bezel = system.config.get_str("bezel", "none")
        if bezel and bezel != "none":
            bz_infos = bezelsUtil.getBezelInfos(rom, bezel, system.name, system.config.emulator)
            if bz_infos is not None and bz_infos["png"].exists():
                commandArray += ["--bezel", str(bz_infos["png"])]

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

