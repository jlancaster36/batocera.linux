import gzip
import tempfile
import unittest
from pathlib import Path
from xml.etree.ElementTree import ParseError

from detect import detect_control


class DetectControlTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.metadata = Path(self.directory.name) / "mame.xml.gz"
        with gzip.open(self.metadata, "wt", encoding="utf-8") as file:
            file.write(
                '<mame><game name="tron"><input control="dial"/></game>'
                '<game name="centiped"><input control="trackball"/></game>'
                '<game name="pacman"><input control="joy4way"/></game>'
                '<game name="empty"/></mame>'
            )

    def detect(self, rom, system="mame", emulator="libretro", core="mame078plus"):
        return detect_control(self.metadata, system, emulator, core, Path(rom))

    def test_detects_dial_and_trackball_in_nested_roms(self):
        self.assertEqual(self.detect("/roms/oldMAME/TRON.ZIP"), "dial")
        self.assertEqual(self.detect("/roms/centiped.7z"), "trackball")

    def test_ignores_unknown_and_non_analog_games(self):
        for rom in ("pacman.zip", "empty.zip", "missing.zip", "tron.txt"):
            with self.subTest(rom=rom):
                self.assertIsNone(self.detect(rom))

    def test_does_not_use_metadata_for_other_emulators(self):
        for kwargs in (
            {"system": "nes"},
            {"emulator": "mame"},
            {"core": "mame"},
        ):
            with self.subTest(kwargs=kwargs):
                self.assertIsNone(self.detect("tron.zip", **kwargs))

    def test_missing_or_invalid_metadata_reports_failure(self):
        self.metadata.unlink()
        with self.assertRaises(FileNotFoundError):
            self.detect("tron.zip")
        with gzip.open(self.metadata, "wt", encoding="utf-8") as file:
            file.write("<mame>")
        with self.assertRaises(ParseError):
            self.detect("tron.zip")


if __name__ == "__main__":
    unittest.main()
