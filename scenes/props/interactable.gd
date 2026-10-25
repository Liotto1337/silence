class_name Interactable
extends StaticBody3D
## Static object reacting to the interact button (bed, TV, front door...).

signal interacted(player: Player)

## Prompt shown on the HUD; empty hides the prompt.
@export var prompt: String = ""
## Optional dynamic prompt; overrides `prompt` when set.
var prompt_provider: Callable


func get_prompt(player: Player) -> String:
	if prompt_provider.is_valid():
		return prompt_provider.call(player)
	return prompt


func interact(player: Player) -> void:
	interacted.emit(player)
