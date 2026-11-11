from __future__ import annotations

import math

from detect import Control


class Motion:
    def __init__(self, mode: Control, width: int = 1024, height: int = 600) -> None:
        self.mode = mode
        self.width = width
        self.height = height
        self.previous: tuple[float, float] | None = None
        self.residual_x = 0.0
        self.residual_y = 0.0

    def release(self) -> None:
        self.previous = None
        self.residual_x = self.residual_y = 0.0

    def move(self, x: float, y: float) -> tuple[int, int]:
        previous = self.previous
        if self.mode == "dial" and math.hypot(
            (x - 0.5) * self.width, (y - 0.5) * self.height
        ) < min(self.width, self.height) * 0.12:
            self.release()
            return 0, 0
        self.previous = (x, y)
        if previous is None:
            return 0, 0
        if self.mode == "dial":
            angle = math.atan2((y - 0.5) * self.height, (x - 0.5) * self.width)
            old_angle = math.atan2(
                (previous[1] - 0.5) * self.height,
                (previous[0] - 0.5) * self.width,
            )
            delta = (angle - old_angle + math.pi) % (2 * math.pi) - math.pi
            self.residual_x += delta * 200
        else:
            self.residual_x += (x - previous[0]) * self.width
            self.residual_y += (y - previous[1]) * self.height

        dx, dy = int(self.residual_x), int(self.residual_y)
        self.residual_x -= dx
        self.residual_y -= dy
        return dx, dy
