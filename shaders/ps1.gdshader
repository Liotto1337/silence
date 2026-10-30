shader_type spatial;
render_mode specular_disabled;
// PlayStation 1 surface: vertices snapped to a coarse grid (the "wobble"), affine texture mapping
// (textures swim on big polygons), nearest-neighbour textures and a box-projected UV so that every
// primitive gets the same texel density without needing authored UVs.
#include "res://shaders/ps1.gdshaderinc"
