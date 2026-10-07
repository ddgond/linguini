// Leaf cards on the Low preset (street_leaves.gdshaderinc): plain Lambert
// light without highlights or light through the leaves.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, diffuse_lambert, specular_disabled;

#define LOW
#include "res://shaders/street_leaves.gdshaderinc"
