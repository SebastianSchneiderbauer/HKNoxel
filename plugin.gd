@tool
extends EditorPlugin

var toolbar_button: Button
var current_noxel: NoxelMap

func _enter_tree() -> void:
	toolbar_button = Button.new()
	toolbar_button.text = "Bake Sound Grid"
	toolbar_button.pressed.connect(_on_bake_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_button)
	toolbar_button.hide()

func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_button)
	toolbar_button.queue_free()

func _handles(object: Object) -> bool:
	var result := object is NoxelMap
	return result

func _edit(object: Object) -> void:
	current_noxel = object as NoxelMap

func _make_visible(visible: bool) -> void:
	toolbar_button.visible = visible

func _on_bake_pressed() -> void:
	if current_noxel:
		current_noxel.bake_sound_grid()
