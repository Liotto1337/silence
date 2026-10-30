class_name HeadLook
extends SkeletonModifier3D
## Turns the neck and head by `yaw` on top of whatever the animation does, so the monster can scan
## the room while it walks or stands. Runs after the AnimationPlayer every frame.

const NECK_SHARE := 0.4

var yaw: float = 0.0
var neck_bone: String = "Neck_014"
var head_bone: String = "Head_015"


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or absf(yaw) < 0.001:
		return
	_turn(skeleton, skeleton.find_bone(neck_bone), yaw * NECK_SHARE)
	_turn(skeleton, skeleton.find_bone(head_bone), yaw * (1.0 - NECK_SHARE))


## Rotates a bone about the world's vertical axis (expressed in skeleton space).
func _turn(skeleton: Skeleton3D, bone: int, angle: float) -> void:
	if bone < 0:
		return
	var up := (skeleton.global_basis.inverse() * Vector3.UP).normalized()
	var global_pose := skeleton.get_bone_global_pose(bone)
	global_pose.basis = Basis(up, angle) * global_pose.basis
	skeleton.set_bone_global_pose(bone, global_pose)
