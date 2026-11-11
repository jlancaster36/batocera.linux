import math
import unittest

from motion import Motion


class MotionTest(unittest.TestCase):
    def test_trackball_relative_movement_and_release(self):
        motion = Motion("trackball")
        self.assertEqual(motion.move(0.1, 0.2), (0, 0))
        self.assertEqual(motion.move(0.2, 0.3), (102, 59))
        motion.release()
        self.assertEqual(motion.move(0.9, 0.8), (0, 0))

    def test_dial_wraps_across_angle_boundary(self):
        motion = Motion("dial")
        motion.move(0.5 + 0.4 * math.cos(math.pi - 0.02),
                    0.5 + 0.4 * math.sin(math.pi - 0.02))
        dx, dy = motion.move(0.5 + 0.4 * math.cos(-math.pi + 0.02),
                             0.5 + 0.4 * math.sin(-math.pi + 0.02))
        self.assertGreater(dx, 0)
        self.assertLess(dx, 10)
        self.assertEqual(dy, 0)

    def test_dial_center_resets_without_jumping(self):
        motion = Motion("dial")
        motion.move(0.9, 0.5)
        self.assertEqual(motion.move(0.5, 0.5), (0, 0))
        self.assertEqual(motion.move(0.5, 0.9), (0, 0))
