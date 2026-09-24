"""Where the street outside the bedroom window goes, in the room model's Godot
coordinates (metres, Y up; the window is in the back wall at z = -1.8, looking
toward -Z). The bedroom is on the third floor, so the street is well below.

   far skyline (downtown towers, hazy)
   second row (taller blocks behind)
   +---------------------+   cross   +----------------------+
   | far row: rowhouses, | street    | corner cafe, more    |   far facades at z = -21.5
   | corner shop         |  (going   | rowhouses            |
   +---------------------+  away)    +----------------------+
   far sidewalk            .  .  .                               z = -16.6 .. -21.5
   parking lane  ============================================
   two traffic lanes -----  - - - - - - - - - - - - - - - -       road: z = -5.8 .. -16.6
   parking lane  ============================================
   our sidewalk (tree, lamps)                                    z = -1.92 .. -5.8
   our building: [window]                                        facade at z = -1.92
"""

ROAD_Y = -6.4          # the road surface: the room floor is 6.4 m up
CURB_H = 0.15
WALK_Y = ROAD_Y + CURB_H

OUR_FACADE_Z = -1.92   # outer face of the bedroom's back wall
NEAR_CURB_Z = -5.8
FAR_CURB_Z = -16.6
FAR_FACADE_Z = -21.5
PARKING = 2.3          # parking lane width, each side
CENTRE_Z = (NEAR_CURB_Z + FAR_CURB_Z) / 2

# The cross street, a T-junction going away from us on the far side.
CROSS_X0 = 8.0         # its left building line
CROSS_X1 = 20.0        # its right building line
CROSS_WALK = 2.6       # its sidewalks
CROSS_END_Z = -130.0

STREET_X = (-90.0, 110.0)  # how far the street runs each way

FLOOR_H = 3.2          # storey height of the rowhouses
GROUND_H = 3.6         # ground floor (shops, raised stoops)

STOOP_OUT = 2.6        # how far stoops reach across the far sidewalk
# People walk along these lines (z): clear of stoops, trees and lamp posts.
WALK_NEAR_Z = -3.0
WALK_FAR_Z = FAR_FACADE_Z + STOOP_OUT + 0.55
