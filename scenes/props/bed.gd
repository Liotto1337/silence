class_name Bed
extends Interactable
## A bed you can crawl under: interact while crouched to hide, interact again to crawl out.
## (The hero's bed also ends the morning: that's the plain interaction, standing up.)

## Local space of the bed: long side along X, the open side (where you get under) at +Z.
var width: float = 1.0


func get_prompt(player: Player) -> String:
	if player.crouching:
		return "Залезть под кровать"
	return super(player)


func interact(player: Player) -> void:
	if player.crouching:
		player.hide_under(self)
	else:
		super(player)


## Where the player lies: in the middle, under the mattress.
func hide_position() -> Vector3:
	return global_transform * Vector3(0, 0.02, -0.1)


## Faces out of the open side.
func hide_yaw() -> float:
	var out := global_basis.z
	return atan2(-out.x, -out.z)


## Where the player ends up after crawling out (crouched, in front of the open side).
func exit_position() -> Vector3:
	return global_transform * Vector3(0, 0.02, width * 0.5 + 0.45)
