extends CanvasLayer
## Full-screen VHS post effect; follows the "VHS-рябь" setting.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(_sync)
	_sync()


func _sync() -> void:
	visible = Settings.vhs_enabled
