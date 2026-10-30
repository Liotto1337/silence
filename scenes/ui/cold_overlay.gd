class_name ColdOverlay
extends CanvasLayer
## Frost on the screen while the player freezes in a vent duct (above the PS1 pass, below the HUD).

@onready var _screen: ColorRect = $Screen


## 0 = warm (overlay off), 1 = frozen to death.
func set_cold(amount: float) -> void:
	_screen.visible = amount > 0.001
	(_screen.material as ShaderMaterial).set_shader_parameter("cold", clampf(amount, 0.0, 1.0))


func get_cold() -> float:
	return (_screen.material as ShaderMaterial).get_shader_parameter("cold") if _screen.visible else 0.0
