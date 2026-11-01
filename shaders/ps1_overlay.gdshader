shader_type spatial;
render_mode specular_disabled, depth_test_disabled;
// PS1 surface drawn over the whole scene, whatever is in front of it (the blanket seen from under it
// is held right in front of the eyes, so the walls of the room must not cut into it).
#include "res://shaders/ps1.gdshaderinc"
