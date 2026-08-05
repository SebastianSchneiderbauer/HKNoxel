@tool
@icon("res://addons/HKNoxel/icon.png")
class_name NoxelMap
extends Node3D

@export var cell_size: float = 1.5
@export_flags_3d_physics var wall_collision_mask: int = 1
@export var saved_data: String = "res://sound_data/"

func bake_sound_grid() -> void:
	var start := -1.5
	var end := 1.5
	var step := 0.1
	var steps := int(round((end - start) / step))
	
	for i in steps + 1:
		var value := start + i * step
		_indexOf(Vector3(value,0,0))

func _indexOf(position : Vector3):
	var test = roundf(position.x / cell_size)
	print(str(position.x) + ": " + str(test))
