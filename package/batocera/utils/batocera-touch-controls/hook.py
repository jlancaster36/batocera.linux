#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import select
import signal
import subprocess
import sys

from detect import detect_control


BASE = Path(__file__).resolve().parent
PIDFILE = Path("/var/run/batocera-touch-controls.pid")
LOG = Path("/userdata/system/logs/touch-controls.log")
METADATA = Path("/userdata/bios/mame2003-plus/mame2003-plus.xml.gz")


def panel_pid() -> int | None:
    if not PIDFILE.exists():
        return None
    pid = int(PIDFILE.read_text().strip())
    try:
        arguments = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except FileNotFoundError:
        PIDFILE.unlink(missing_ok=True)
        return None
    if os.fsencode(BASE / "panel.py") not in arguments:
        raise RuntimeError(f"Refusing to signal unrelated process {pid}")
    return pid


def stop_panel() -> None:
    pid = panel_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            PIDFILE.unlink(missing_ok=True)


def main() -> None:
    if len(sys.argv) != 6:
        raise ValueError("Expected event, system, emulator, core and ROM")
    event, system, emulator, core, rom = sys.argv[1:]
    if event == "gameStop":
        stop_panel()
        return
    if event != "gameStart":
        return
    control = detect_control(METADATA, system, emulator, core, Path(rom))
    if control is None:
        return
    if panel_pid() is not None:
        raise RuntimeError("Touch controls are already running")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as log:
        process = subprocess.Popen(
            [sys.executable, str(BASE / "panel.py"), control, str(os.getppid())],
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
        )
        assert process.stdout is not None
        ready, _, _ = select.select([process.stdout], [], [], 10)
        if not ready or process.stdout.readline().strip() != "READY":
            process.terminate()
            process.wait(timeout=5)
            raise RuntimeError(f"Touch control startup failed; see {LOG}")
        process.stdout.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"touch-controls: {error}", file=sys.stderr)
        sys.exit(1)
