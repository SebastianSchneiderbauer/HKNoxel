@tool
class_name NoxelClusterStorage
extends Resource

## Bumped whenever the baked layout changes, so older bakes are rebuilt instead of misread.
const FORMAT_VERSION: int = 2
## Free cells that no box has claimed yet. Only exists while building.
const UNASSIGNED: int = -2

## One ID per fine cell. Walls use -1; every free cell belongs to one box.
@export var cell_to_cluster: PackedInt32Array
@export var cluster_origins: PackedInt32Array
## Box size in cells, three entries (x, y, z) per cluster.
@export var cluster_sizes: PackedInt32Array
## Compact adjacency: neighbors of cluster i occupy [offsets[i], offsets[i + 1]).
@export var neighbor_offsets: PackedInt32Array
@export var neighbor_ids: PackedInt32Array
## Face each neighbor is reached through, as a direction index of open_side_masks.
@export var neighbor_directions: PackedByteArray
## Bits +X, -X, +Y, -Y, +Z, -Z. A face counts once regardless of neighbor count.
@export var open_side_masks: PackedByteArray

@export var grid_dimensions: Vector3i
@export var max_side_cells: int
@export var wall_checksum: int
@export var format_version: int

## Written while build() runs so another thread can poll it for a progress bar.
var build_progress: float = 0.0

func get_cluster_count() -> int:
	return cluster_origins.size()

func is_compatible(walls: NoxelWallStorage, dimensions: Vector3i, side_limit: int) -> bool:
	var cluster_count: int = cluster_origins.size()
	return walls != null \
		and format_version == FORMAT_VERSION \
		and grid_dimensions == dimensions \
		and max_side_cells == side_limit \
		and wall_checksum == hash(walls._wallInformation) \
		and cell_to_cluster.size() == dimensions.x * dimensions.y * dimensions.z \
		and cluster_sizes.size() == cluster_count * 3 \
		and open_side_masks.size() == cluster_count \
		and neighbor_offsets.size() == cluster_count + 1 \
		and neighbor_offsets[cluster_count] == neighbor_ids.size() \
		and neighbor_directions.size() == neighbor_ids.size()

## Partitions the free cells into boxes of at most side_limit cells per axis.
## Touches nothing but this resource, so it can run on a worker thread.
func build(walls: NoxelWallStorage, dimensions: Vector3i, side_limit: int) -> void:
	build_progress = 0.0
	grid_dimensions = dimensions
	max_side_cells = maxi(1, side_limit)
	wall_checksum = hash(walls._wallInformation)
	format_version = FORMAT_VERSION
	var width: int = dimensions.x
	var height: int = dimensions.y
	var depth: int = dimensions.z
	var plane: int = width * height
	var cell_count: int = plane * depth
	var wall_bits: PackedByteArray = walls._wallInformation
	cluster_origins.clear()
	cluster_sizes.clear()
	neighbor_offsets.clear()
	neighbor_ids.clear()
	neighbor_directions.clear()
	open_side_masks.clear()
	
	# Every free cell starts unclaimed; only walls need writing individually.
	cell_to_cluster.resize(cell_count)
	cell_to_cluster.fill(UNASSIGNED)
	
	# largest_cube holds the side of the largest wall-free cube whose lowest
	# corner is that cell (walls only, capped). It is padded by one zero layer on
	# the high side of each axis so no bounds checks are needed, and walked
	# backwards so the seven cells each entry depends on are already known. Four
	# of them were read by the previous cell in the row and are carried along.
	var padded_width: int = width + 1
	var padded_plane: int = padded_width * (height + 1)
	var largest_cube: PackedInt32Array
	largest_cube.resize(padded_plane * (depth + 1))
	var candidates: PackedInt32Array
	var candidate_sides: PackedInt32Array
	for z: int in range(depth - 1, -1, -1):
		for y: int in range(height - 1, -1, -1):
			var row: int = y * width + z * plane
			var padded_row: int = y * padded_width + z * padded_plane
			var right: int = 0
			var up_right: int = 0
			var back_right: int = 0
			var back_up_right: int = 0
			for x: int in range(width - 1, -1, -1):
				var cell: int = row + x
				var padded: int = padded_row + x
				var up: int = largest_cube[padded + padded_width]
				var back: int = largest_cube[padded + padded_plane]
				var back_up: int = largest_cube[padded + padded_width + padded_plane]
				var cube: int = 0
				if (wall_bits[cell >> 3] & (1 << (cell & 7))) != 0:
					cell_to_cluster[cell] = -1
				else:
					cube = right
					if up < cube: cube = up
					if back < cube: cube = back
					if up_right < cube: cube = up_right
					if back_right < cube: cube = back_right
					if back_up < cube: cube = back_up
					if back_up_right < cube: cube = back_up_right
					cube += 1
					if cube > max_side_cells: cube = max_side_cells
					largest_cube[padded] = cube
					if cube >= 2:
						candidates.append(cell)
						candidate_sides.append(cube)
				right = cube
				up_right = up
				back_right = back
				back_up_right = back_up
		build_progress = 0.1 * float(depth - z) / float(depth)
	largest_cube.clear()
	candidates.reverse()
	candidate_sides.reverse()
	
	# Largest cubes first, each stretched into a box right away, so big open
	# spaces are not cut up by whatever the scan order reaches first. Every box
	# placed so far is at least `side` cells on each axis, so it can only overlap
	# a wall-free cube of this side by covering one of the cube's corners.
	var pass_count: int = maxi(1, max_side_cells - 1)
	for side: int in range(max_side_cells, 1, -1):
		var far: int = side - 1
		var far_y: int = far * width
		var far_z: int = far * plane
		var kept: int = 0
		var candidate_count: int = candidates.size()
		for i: int in candidate_count:
			if (i & 4095) == 0:
				build_progress = 0.1 + 0.4 * (float(max_side_cells - side) + float(i) / float(candidate_count)) / float(pass_count)
			var origin: int = candidates[i]
			if cell_to_cluster[origin] != UNASSIGNED:
				continue
			if candidate_sides[i] >= side \
					and cell_to_cluster[origin + far] == UNASSIGNED \
					and cell_to_cluster[origin + far_y] == UNASSIGNED \
					and cell_to_cluster[origin + far_z] == UNASSIGNED \
					and cell_to_cluster[origin + far + far_y] == UNASSIGNED \
					and cell_to_cluster[origin + far + far_z] == UNASSIGNED \
					and cell_to_cluster[origin + far_y + far_z] == UNASSIGNED \
					and cell_to_cluster[origin + far + far_y + far_z] == UNASSIGNED:
				_claim_box(origin, Vector3i(side, side, side))
				continue
			if side > 2:
				candidates[kept] = origin
				candidate_sides[kept] = candidate_sides[i]
				kept += 1
		candidates.resize(kept)
		candidate_sides.resize(kept)
	
	# Whatever is left (one-cell gaps and awkward corners) becomes boxes in scan
	# order.
	for z: int in depth:
		for y: int in height:
			var row: int = y * width + z * plane
			for x: int in width:
				if cell_to_cluster[row + x] == UNASSIGNED:
					_claim_box(row + x, Vector3i.ONE)
		build_progress = 0.5 + 0.1 * float(z + 1) / float(depth)
	
	_build_neighbors()
	build_progress = 1.0

## Grows a box from its current size along +X, then +Y, then +Z while the new
## face is unclaimed free space, then assigns its cells to a new cluster.
func _claim_box(origin: int, size: Vector3i) -> void:
	var width: int = grid_dimensions.x
	var plane: int = width * grid_dimensions.y
	var x: int = origin % width
	var y: int = (origin / width) % grid_dimensions.y
	var z: int = origin / plane
	var fits: bool = true
	while fits and size.x < max_side_cells and x + size.x < grid_dimensions.x:
		var face: int = origin + size.x
		for dz: int in size.z:
			for dy: int in size.y:
				if cell_to_cluster[face + dy * width + dz * plane] != UNASSIGNED:
					fits = false
					break
			if not fits:
				break
		if fits:
			size.x += 1
	fits = true
	while fits and size.y < max_side_cells and y + size.y < grid_dimensions.y:
		var face: int = origin + size.y * width
		for dz: int in size.z:
			var row: int = face + dz * plane
			for dx: int in size.x:
				if cell_to_cluster[row + dx] != UNASSIGNED:
					fits = false
					break
			if not fits:
				break
		if fits:
			size.y += 1
	fits = true
	while fits and size.z < max_side_cells and z + size.z < grid_dimensions.z:
		var face: int = origin + size.z * plane
		for dy: int in size.y:
			var row: int = face + dy * width
			for dx: int in size.x:
				if cell_to_cluster[row + dx] != UNASSIGNED:
					fits = false
					break
			if not fits:
				break
		if fits:
			size.z += 1
	
	var cluster_id: int = cluster_origins.size()
	cluster_origins.append(origin)
	cluster_sizes.append(size.x)
	cluster_sizes.append(size.y)
	cluster_sizes.append(size.z)
	for dz: int in size.z:
		for dy: int in size.y:
			var row: int = origin + dy * width + dz * plane
			for dx: int in size.x:
				cell_to_cluster[row + dx] = cluster_id

func _build_neighbors() -> void:
	var width: int = grid_dimensions.x
	var height: int = grid_dimensions.y
	var depth: int = grid_dimensions.z
	var plane: int = width * height
	var cluster_count: int = cluster_origins.size()
	var seen: PackedInt32Array
	seen.resize(cluster_count)
	seen.fill(-1)
	neighbor_offsets.resize(cluster_count + 1)
	neighbor_offsets[0] = 0
	open_side_masks.resize(cluster_count)
	
	for cluster_id: int in cluster_count:
		var origin: int = cluster_origins[cluster_id]
		var size_x: int = cluster_sizes[cluster_id * 3]
		var size_y: int = cluster_sizes[cluster_id * 3 + 1]
		var size_z: int = cluster_sizes[cluster_id * 3 + 2]
		var x: int = origin % width
		var y: int = (origin / width) % height
		var z: int = origin / plane
		var mask: int = 0
		for direction: int in 6:
			# Walk the layer of cells just outside one face as a u/v grid.
			var start: int
			var u_step: int
			var u_count: int
			var v_step: int
			var v_count: int
			if direction < 2:
				if (direction == 0 and x + size_x >= width) or (direction == 1 and x == 0):
					continue
				start = origin + size_x if direction == 0 else origin - 1
				u_step = width
				u_count = size_y
				v_step = plane
				v_count = size_z
			elif direction < 4:
				if (direction == 2 and y + size_y >= height) or (direction == 3 and y == 0):
					continue
				start = origin + size_y * width if direction == 2 else origin - width
				u_step = 1
				u_count = size_x
				v_step = plane
				v_count = size_z
			else:
				if (direction == 4 and z + size_z >= depth) or (direction == 5 and z == 0):
					continue
				start = origin + size_z * plane if direction == 4 else origin - plane
				u_step = 1
				u_count = size_x
				v_step = width
				v_count = size_y
			for v: int in v_count:
				var row: int = start + v * v_step
				for u: int in u_count:
					var neighbor: int = cell_to_cluster[row + u * u_step]
					if neighbor < 0:
						continue
					mask |= 1 << direction
					# Two boxes can only touch through one face, so this is also
					# the only direction this neighbor is recorded under.
					if seen[neighbor] != cluster_id:
						seen[neighbor] = cluster_id
						neighbor_ids.append(neighbor)
						neighbor_directions.append(direction)
		open_side_masks[cluster_id] = mask
		neighbor_offsets[cluster_id + 1] = neighbor_ids.size()
		if (cluster_id & 1023) == 0:
			build_progress = 0.6 + 0.4 * float(cluster_id + 1) / float(cluster_count)
