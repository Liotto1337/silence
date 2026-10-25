extends Node
## Global noise channel. Anything audible to the monster reports here; the monster decides
## whether it actually heard it (distance + wall occlusion).

## radius: how far (in metres, unoccluded) the noise carries.
signal noise_emitted(position: Vector3, radius: float, source: Node)

## Typical radii, so loudness stays consistent across systems.
const SPRINT_STEP := 9.0
const JUMP_LANDING := 6.0
const IMPACT_MIN := 4.0
const IMPACT_MAX := 14.0
const DUCK_SQUEAK := 15.0
const TV := 20.0


func emit_noise(position: Vector3, radius: float, source: Node = null) -> void:
	noise_emitted.emit(position, radius, source)
