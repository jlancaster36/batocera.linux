import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import hook


class HookTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.pidfile = Path(self.directory.name) / "panel.pid"
        self.patch = patch.object(hook, "PIDFILE", self.pidfile)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_removes_stale_pidfile(self):
        self.pidfile.write_text("12345")
        with patch.object(Path, "read_bytes", side_effect=FileNotFoundError):
            self.assertIsNone(hook.panel_pid())
        self.assertFalse(self.pidfile.exists())

    def test_will_not_signal_an_unrelated_process(self):
        self.pidfile.write_text("12345")
        with patch.object(Path, "read_bytes", return_value=b"other-process\0"):
            with patch.object(os, "kill") as kill:
                with self.assertRaises(RuntimeError):
                    hook.stop_panel()
                kill.assert_not_called()
        self.assertTrue(self.pidfile.exists())

    def test_signals_our_panel(self):
        self.pidfile.write_text("12345")
        cmdline = b"python3\0" + os.fsencode(hook.BASE / "panel.py") + b"\0"
        with patch.object(Path, "read_bytes", return_value=cmdline):
            with patch.object(os, "kill") as kill:
                hook.stop_panel()
                kill.assert_called_once_with(12345, hook.signal.SIGTERM)
