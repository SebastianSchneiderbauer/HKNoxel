@tool
extends EditorPlugin
const NOXEL_MAP_SCRIPT_PATH := "res://addons/HKNoxel/HKNoxel.gd"
var toolbar_button: Button
var debug_bake_button: Button
var remove_debug_button: Button
var current_noxel: Node3D
func _enter_tree() -> void:
	toolbar_button = Button.new()
	toolbar_button.text = "Bake Sound Grid"
	toolbar_button.pressed.connect(_on_bake_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_button)
	toolbar_button.hide()
	
	debug_bake_button = Button.new()
	debug_bake_button.text = "Bake with Debug Visualization"
	debug_bake_button.pressed.connect(_on_bake_debug_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, debug_bake_button)
	debug_bake_button.hide()
	
	remove_debug_button = Button.new()
	remove_debug_button.text = "Remove Debug Visualization"
	remove_debug_button.pressed.connect(_on_remove_debug_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, remove_debug_button)
	remove_debug_button.hide()
func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar_button)
	toolbar_button.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, debug_bake_button)
	debug_bake_button.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, remove_debug_button)
	remove_debug_button.queue_free()
func _handles(object: Object) -> bool:
	return _is_noxel_map(object)
func _edit(object: Object) -> void:
	current_noxel = object as Node3D if _is_noxel_map(object) else null
func _make_visible(visible: bool) -> void:
	toolbar_button.visible = visible
	debug_bake_button.visible = visible
	remove_debug_button.visible = visible
func _on_bake_pressed() -> void:
	var noxel := _selected_noxel_map()
	if noxel:
		noxel.call("bake_sound_grid")
func _on_bake_debug_pressed() -> void:
	var noxel := _selected_noxel_map()
	if noxel:
		noxel.call("bake_sound_grid", true)
func _on_remove_debug_pressed() -> void:
	var noxel := _selected_noxel_map()
	if noxel:
		noxel.call("remove_debug_visualization")

func _is_noxel_map(object: Object) -> bool:
	if not object is Node3D:
		return false
	var script: Script = object.get_script()
	return script != null and script.resource_path == NOXEL_MAP_SCRIPT_PATH

func _selected_noxel_map() -> Node3D:
	var selection := EditorInterface.get_selection()
	if selection:
		var selected_nodes := selection.get_selected_nodes()
		if not selected_nodes.is_empty():
			current_noxel = null
			for node in selected_nodes:
				if _is_noxel_map(node):
					current_noxel = node
					break
	if not is_instance_valid(current_noxel) or not current_noxel.is_inside_tree() or not _is_noxel_map(current_noxel):
		push_error("HKNoxel: select a NoxelMap node before using the toolbar.")
		return null
	if not current_noxel.has_method("bake_sound_grid") or not current_noxel.has_method("remove_debug_visualization"):
		push_error("HKNoxel: the selected NoxelMap script is not active. Reload the script or reopen the scene, then reselect the map.")
		return null
	return current_noxel
