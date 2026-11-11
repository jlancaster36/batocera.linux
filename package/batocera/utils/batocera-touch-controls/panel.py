#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time

os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
os.environ["SDL_VIDEODRIVER"] = "wayland"

import evdev
from evdev import ecodes
import pygame
import pyudev

from detect import Control
from motion import Motion


TITLE = "Batocera Touch Controls"
PIDFILE = Path("/var/run/batocera-touch-controls.pid")
MOUSE_NAME = "Batocera Touch Controls"
running = True


def stop(_signum: int, _frame: object) -> None:
    global running
    running = False


def sway(*args: str) -> object:
    result = subprocess.run(
        ["swaymsg", *args], check=True, capture_output=True, text=True, timeout=5
    )
    data = json.loads(result.stdout)
    if isinstance(data, list) and any(
        isinstance(item, dict) and item.get("success") is False for item in data
    ):
        raise RuntimeError(f"Sway command failed: {data}")
    return data


def setting(name: str) -> str:
    return subprocess.run(
        ["batocera-settings-get", name], check=True, capture_output=True,
        text=True, timeout=5
    ).stdout.strip()


def select_devices() -> evdev.InputDevice:
    context = pyudev.Context()
    touches = []
    mice = []
    for device in context.list_devices(subsystem="input"):
        node = device.device_node
        if not node or not re.fullmatch(r"/dev/input/event\d+", node):
            continue
        if device.get("ID_INPUT_TOUCHSCREEN") == "1":
            touches.append(node)
        elif device.get("ID_INPUT_MOUSE") == "1" or device.get("ID_INPUT_TOUCHPAD") == "1":
            mice.append(node)
    if mice:
        raise RuntimeError(f"Existing mouse or touchpad would conflict with player 1: {mice}")
    if len(touches) != 1:
        raise RuntimeError(f"Expected exactly one touchscreen, found {touches}")
    return evdev.InputDevice(touches[0])


def window_id(node: dict) -> int | None:
    if node.get("name") == TITLE:
        return node["id"]
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = window_id(child)
        if found is not None:
            return found
    return None


def main(mode: Control, parent: int) -> None:
    primary = setting("global.videooutput")
    secondary = setting("global.videooutput2")
    outputs = sway("-t", "get_outputs")
    if not isinstance(outputs, list):
        raise RuntimeError("Unexpected Sway output list")
    active = {item["name"]: item for item in outputs if item.get("active")}
    if primary == secondary or primary not in active or secondary not in active:
        raise RuntimeError("Primary and secondary outputs must both be active")
    if active[secondary].get("transform") != "normal":
        raise RuntimeError("Rotated touch displays are not supported")
    width = active[secondary]["rect"]["width"]
    height = active[secondary]["rect"]["height"]
    touch = select_devices()
    mouse = None
    grabbed = False
    try:
        x_info = touch.absinfo(ecodes.ABS_X)
        y_info = touch.absinfo(ecodes.ABS_Y)
        if x_info.max <= x_info.min or y_info.max <= y_info.min:
            raise RuntimeError("Invalid touchscreen axis range")
        touch.grab()
        grabbed = True
        mouse = evdev.UInput(
            {ecodes.EV_KEY: [ecodes.BTN_LEFT],
             ecodes.EV_REL: [ecodes.REL_X, ecodes.REL_Y]},
            name=MOUSE_NAME,
        )
        context = pyudev.Context()
        for _ in range(50):
            device = pyudev.Devices.from_device_file(context, mouse.device.path)
            if device.get("ID_INPUT_MOUSE") == "1":
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Virtual mouse was not registered by udev")

        pygame.display.init()
        pygame.font.init()
        screen = pygame.display.set_mode((width, height))
        pygame.display.set_caption(TITLE)
        font = pygame.font.Font(None, max(28, height // 18))
        center = (width // 2, height // 2)
        radius = min(width, height) * 2 // 5
        label = "SPINNER" if mode == "dial" else "TRACKBALL"
        help_text = "Drag around the dial to turn" if mode == "dial" else "Swipe in any direction"
        labels = [
            (font.render(text, True, (235, 248, 255)), y_pos)
            for text, y_pos in ((label, height // 12), (help_text, height * 11 // 12))
        ]

        def draw(position: tuple[float, float] | None = None) -> None:
            screen.fill((10, 17, 31))
            if mode == "dial":
                pygame.draw.circle(screen, (29, 42, 58), center, radius)
                pygame.draw.circle(screen, (66, 207, 220), center, radius, 6)
                for tick in range(24):
                    angle = tick * math.tau / 24
                    start = (center[0] + int(radius * 0.80 * math.cos(angle)),
                             center[1] + int(radius * 0.80 * math.sin(angle)))
                    end = (center[0] + int(radius * 0.94 * math.cos(angle)),
                           center[1] + int(radius * 0.94 * math.sin(angle)))
                    pygame.draw.line(screen, (120, 213, 221), start, end, 3)
                pygame.draw.circle(screen, (52, 89, 106), center, radius * 2 // 3)
                pygame.draw.circle(screen, (120, 213, 221), center, radius // 10)
            else:
                pygame.draw.circle(screen, (34, 111, 143), center, radius)
                pygame.draw.circle(screen, (127, 224, 232), center, radius, 6)
                pygame.draw.ellipse(
                    screen, (76, 172, 190),
                    pygame.Rect(center[0] - radius // 2, center[1] - radius,
                                radius, radius * 2), 3
                )
                pygame.draw.ellipse(
                    screen, (76, 172, 190),
                    pygame.Rect(center[0] - radius, center[1] - radius // 3,
                                radius * 2, radius * 2 // 3), 3
                )
                pygame.draw.circle(
                    screen, (184, 238, 241),
                    (center[0] - radius // 3, center[1] - radius // 3),
                    max(8, radius // 12)
                )
            if position is not None:
                point = (int(position[0] * width), int(position[1] * height))
                if mode == "dial":
                    pygame.draw.line(screen, (66, 207, 220), center, point, 4)
                pygame.draw.circle(screen, (235, 248, 255), point, 12)
            for image, y_pos in labels:
                screen.blit(image, image.get_rect(center=(width // 2, y_pos)))
            pygame.display.flip()

        draw()
        for _ in range(30):
            pygame.event.pump()
            tree = sway("-t", "get_tree")
            if not isinstance(tree, dict):
                raise RuntimeError("Unexpected Sway tree")
            wid = window_id(tree)
            if wid is not None:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Touch control window not found in Sway")
        sway(f'[con_id={wid}] move container to output "{secondary}"')
        sway(f"[con_id={wid}] fullscreen enable")
        sway(f'focus output "{primary}"')
        PIDFILE.write_text(str(os.getpid()), encoding="ascii")
        print("READY", flush=True)

        motion = Motion(mode, width, height)
        x = y = None
        down = False
        position = None
        dirty = False
        next_draw = 0.0
        while running and Path(f"/proc/{parent}").exists():
            pygame.event.pump()
            ready, _, _ = select.select([touch.fd], [], [], 0.02)
            for event in touch.read() if ready else ():
                if event.type == ecodes.EV_ABS:
                    if event.code == ecodes.ABS_X:
                        x = (event.value - x_info.min) / (x_info.max - x_info.min)
                    elif event.code == ecodes.ABS_Y:
                        y = (event.value - y_info.min) / (y_info.max - y_info.min)
                elif event.type == ecodes.EV_KEY and event.code == ecodes.BTN_TOUCH:
                    down = bool(event.value)
                    if not down:
                        motion.release()
                        position = None
                        dirty = True
                elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_DROPPED:
                    motion.release()
                    down = False
                    position = None
                    dirty = True
                elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
                    if down and x is not None and y is not None:
                        dx, dy = motion.move(x, y)
                        if dx:
                            mouse.write(ecodes.EV_REL, ecodes.REL_X, dx)
                        if dy:
                            mouse.write(ecodes.EV_REL, ecodes.REL_Y, dy)
                        if dx or dy:
                            mouse.syn()
                        position = (x, y)
                        dirty = True
            now = time.monotonic()
            if dirty and now >= next_draw:
                draw(position)
                dirty = False
                next_draw = time.monotonic() + 1 / 30
    finally:
        if PIDFILE.exists() and PIDFILE.read_text().strip() == str(os.getpid()):
            PIDFILE.unlink()
        pygame.quit()
        if mouse is not None:
            mouse.close()
        if grabbed:
            touch.ungrab()
        touch.close()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if len(sys.argv) != 3 or sys.argv[1] not in ("dial", "trackball"):
        raise SystemExit("Expected control mode and launcher PID")
    main(sys.argv[1], int(sys.argv[2]))
