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
@export_category("DO NOT TOUCH")
@export var wallBakeData : NoxelWallStorage

var vGridStartPosition: Vector3
var vGridDimensions: Vector3i # the dimensions of our voxelgrid
var _debug_positions: PackedVector3Array
func bake_sound_grid(debug: bool = false) -> void:
	# init
	var start_time := Time.get_ticks_usec()
	if debug:
		remove_debug_visualization()
		_debug_positions = PackedVector3Array()

	# get dimensions
	if not AABBProvider:
		printerr("no AABBProvider was provided")
		return
	var dimensions : AABB = _get_node_aabb(AABBProvider)
	vGridStartPosition = dimensions.position
	vGridDimensions = (dimensions.size / cell_size).ceil()
	
	# bake walls
	_init_bake_query()
	var totalCount := vGridDimensions.x * vGridDimensions.y * vGridDimensions.z
	wallBakeData = NoxelWallStorage.new(totalCount)
	var wallcount : int
	print("Iterating over " + str(totalCount) + " cells. This could take some time on old hardware...")
	for z in vGridDimensions.z: # beautiful
		for y in vGridDimensions.y:
			for x in vGridDimensions.x:
				if _is_cell_occupied(vGridStartPosition + Vector3(x,y,z) * cell_size):
					wallcount += 1;
					wallBakeData.updateWall(_indexOf(Vector3(x,y,z)), true)
					
					if debug:
						_debug_positions.push_back(vGridStartPosition + Vector3(x,y,z) * cell_size)

	if debug:
		_build_debug_multimesh()

	# final message
	var elapsed_usec := Time.get_ticks_usec() - start_time
	print("finished: " + str(wallcount) + "/" + str(totalCount) + " cells were detected as walls in " + str(elapsed_usec / 1000.0) + " ms")
func remove_debug_visualization():
	for child in get_children():
		child.queue_free()
const DEBUG_MESH = preload("res://addons/HKNoxel/debugMesh.tscn")
## Draws all debug cells in a single MultiMeshInstance3D instead of one node per cell, avoiding per-cell scene-tree overhead
func _build_debug_multimesh() -> void:
	var template := DEBUG_MESH.instantiate()
	var mesh: Mesh = template.mesh.duplicate()
	mesh.size = Vector3(cell_size, cell_size, cell_size)
	template.queue_free()

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _debug_positions.size()
	for i in _debug_positions.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), _debug_positions[i]))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	add_child(mmi)
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
