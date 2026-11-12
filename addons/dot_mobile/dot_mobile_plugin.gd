@tool
extends EditorPlugin

## Editor entry point for dot-mobile. Registers inspector types only; no autoloads, a game adds the overlay itself.

const _TYPES := [
	["DotMobileControls", "Control", "res://addons/dot_mobile/runtime/dot_mobile_controls.gd"],
]


func _enter_tree() -> void:
	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), null)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
