from __future__ import annotations

import gzip
from pathlib import Path
from typing import Literal
from xml.etree import ElementTree


Control = Literal["dial", "trackball"]


def detect_control(
    metadata: Path, system: str, emulator: str, core: str, rom: Path
) -> Control | None:
    if system != "mame" or emulator != "libretro" or core != "mame078plus":
        return None
    if rom.suffix.lower() not in {".zip", ".7z"}:
        return None

    with gzip.open(metadata, "rb") as source:
        for _, element in ElementTree.iterparse(source, events=("end",)):
            if element.tag != "game":
                continue
            if element.get("name") == rom.stem.lower():
                input_element = element.find("input")
                if input_element is None:
                    return None
                control = input_element.get("control")
                if control == "dial":
                    return "dial"
                if control == "trackball":
                    return "trackball"
                return None
            element.clear()

    return None
