@tool
@icon("res://addons/HKNoxel/icon.png")
class_name NoxelMap
extends Node3D

@export var cell_size: float = 1.5
@export_flags_3d_physics var wall_collision_mask: int = 1
@export var AABBProvider: Node3D
func bake_sound_grid() -> void:
	if AABBProvider:
		dimensions = get_node_aabb(AABBProvider)
		print(dimensions)
	else:
		printerr("no AABBProvider was provided")

var dimensions: AABB
func _indexOf(position : Vector3):
	if AABBProvider:
		dimensions = get_node_aabb(AABBProvider)
	else:
		return
	var test = roundf(position.x / cell_size)
	print(str(position.x) + ": " + str(test))

# partly ported from a github issue, but modified
func get_node_aabb(node: Node3D, ignore_top_level: bool = true) -> AABB:
	var box: AABB
	var has_box := false
	
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		box = vi.global_transform * vi.get_aabb()
		has_box = true
	
	for i: int in node.get_child_count():
		var child := node.get_child(i) as Node3D
		if child and not (ignore_top_level and child.top_level):
			var child_box := get_node_aabb(child, ignore_top_level)
			if child_box.size != Vector3.ZERO or child_box.position != Vector3.ZERO:
				if has_box:
					box = box.merge(child_box)
				else:
					box = child_box
					has_box = true
	
	return box
