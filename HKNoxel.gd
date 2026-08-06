@tool
@icon("res://addons/HKNoxel/icon.png")
class_name NoxelMap
extends Node3D

## The size of the sound voxels.
@export var cell_size: float = 1.5
## What the baking process sees as walls. Its recommended to have seperate layers for decoration and actual walls, so props dont block Noxels
@export_flags_3d_physics var wall_collision_mask: int = 1
## The node that defines the bounding box of the map. Merges its childrens AABBs, so make sure there are actual providers as children.
@export var AABBProvider: Node3D

var vGridStartPosition: Vector3
var vGridDimensions: Vector3i # the dimensions of our voxelgrid
func bake_sound_grid() -> void:
	if not AABBProvider:
		printerr("no AABBProvider was provided")
		return
	var dimensions : AABB = _get_node_aabb(AABBProvider)
	vGridStartPosition = dimensions.position
	vGridDimensions = (dimensions.size / cell_size).ceil()
	
	var totalCount := vGridDimensions.x * vGridDimensions.y * vGridDimensions.z
	print("Iterating over " + str(totalCount) + " cells. this may take some time")
	for z in vGridDimensions.z:
		for y in vGridDimensions.y:
			for x in vGridDimensions.x:
				totalCount -= 1
	print("finished: ")

## Converting a global position into a id
func _indexOf(objectPosition: Vector3) -> int:
	if vGridDimensions == Vector3i.ZERO:
		printerr("cannot get index if dimensions were not specified")
		return -1
	
	var relativePosition: Vector3 = objectPosition - vGridStartPosition
	var voxelPosition: Vector3 = (relativePosition / cell_size).round()
	return int(voxelPosition.x + voxelPosition.y * vGridDimensions.x + voxelPosition.z * vGridDimensions.x * vGridDimensions.y)
## Converts a id of a Noxel chunk into a worldposition. Keep in mind this always returns the center of said chunk
func _positionOf(index: int) -> Vector3:
	if vGridDimensions == Vector3i.ZERO:
		printerr("cannot get position if dimensions were not specified")
		return Vector3.ZERO
	
	var width := vGridDimensions.x
	var height := vGridDimensions.y
	
	var x := index % width
	var y := (index / width) % height
	var z := index / (width * height)
	
	return vGridStartPosition + Vector3(x, y, z) * cell_size
## Returns the combined AABB of a nodes children
func _get_node_aabb(node: Node3D, ignore_top_level: bool = true) -> AABB:
	var box: AABB
	var has_box := false
	
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		box = vi.global_transform * vi.get_aabb()
		has_box = true
	
	for i: int in node.get_child_count():
		var child := node.get_child(i) as Node3D
		if child and not (ignore_top_level and child.top_level):
			var child_box := _get_node_aabb(child, ignore_top_level)
			if child_box.size != Vector3.ZERO or child_box.position != Vector3.ZERO:
				if has_box:
					box = box.merge(child_box)
				else:
					box = child_box
					has_box = true
	
	return box

var _query_shape: BoxShape3D
var _query_params: PhysicsShapeQueryParameters3D
## Sets up our wallcheck query
func _init_bake_query() -> void:
	_query_shape = BoxShape3D.new()
	_query_shape.size = Vector3.ONE * cell_size
	
	_query_params = PhysicsShapeQueryParameters3D.new()
	_query_params.shape = _query_shape
	_query_params.collision_mask = wall_collision_mask
	_query_params.margin = 0.0
## Executes the wallcheck query
func _is_cell_occupied(cell_center: Vector3) -> bool:
	_query_params.transform = Transform3D(Basis(), cell_center)
	var space_state := get_world_3d().direct_space_state
	var hits := space_state.intersect_shape(_query_params, 1)
	return hits.size() > 0
