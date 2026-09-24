"""Where everything in the bedroom goes, in Godot coordinates (metres, Y up,
the room camera looks toward -Z at the back wall).

      back wall (z = -1.8), window over the tank
  +--------------[=========]---------------+
  | shelf      [   TANK on stand   ]  plant |
  | nightstand                     +------+ |
  | [bed]          rug     beanbag |desk  | |
  |  plush                         |mon < | |   the monitor faces -X, toward
  |                                |chat  | |   the tank's right-hand glass
  | door        (o) room camera    +------+ |
  +-----------------------------------------+   front wall (z = 1.8)

The points Godot needs (tank, screen, speakers, room camera, light
positions) are exported with the room as glTF extras, so the game reads them
from here instead of keeping its own copy.
"""

ROOM_MIN = (-2.1, 0.0, -1.8)
ROOM_MAX = (2.1, 2.6, 1.8)
WALL = 0.12

# The tank's origin is the inside bottom of the tank (see art/models/tank.py).
TANK_ORIGIN = (-0.15, 0.8, -1.44)
TANK_SIZE = (1.3, 1.5, 0.64)  # stand + tank + hood, for the bake's stand-in

WINDOW_CENTER_X = -0.15
WINDOW_WIDTH = 1.9
WINDOW_SILL = 0.95
WINDOW_TOP = 2.25

DESK_MIN = (1.4, 0.0, -1.78)
DESK_MAX = (2.1, 0.76, 0.0)

SCREEN_CENTER = (1.86, 1.13, -1.2)  # faces -X
SCREEN_SIZE = (0.8, 0.45)
SPEAKERS = [(1.9, 0.89, -1.7), (1.9, 0.89, -0.7)]
CHAT_SCREEN = (1.9, 1.06, -0.42)
ROOM_CAMERA = (-0.15, 1.08, 0.16)

BED_MIN = (-2.1, 0.0, -1.0)
BED_MAX = (-1.1, 0.5, 1.0)
DOOR_CENTER_X = -1.5
DOOR_WIDTH = 0.86
DOOR_HEIGHT = 2.05

# Light sources the moods use (both baked and live).
FLOOR_LAMP = (1.85, 1.45, 1.52)
BEDSIDE_LAMP = (-1.85, 0.72, -1.25)
CEILING_LIGHT = (0.0, 2.55, 0.0)
MONITOR_GLOW = (1.6, 1.13, -1.2)
RGB_STRIP = (2.05, 2.45, -0.9)
BIAS_LIGHT = (2.05, 1.13, -1.2)
FAIRY_WINDOW_Y = 2.33
