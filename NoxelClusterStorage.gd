@tool
class_name NoxelClusterStorage
extends Resource

## One ID per fine cell. Walls use -1; every free cell belongs to one cube.
@export var cell_to_cluster: PackedInt32Array
@export var cluster_origins: PackedInt32Array
@export var cluster_sides: PackedInt32Array
## Compact adjacency: neighbors of cluster i occupy [offsets[i], offsets[i + 1]).
@export var neighbor_offsets: PackedInt32Array
@export var neighbor_ids: PackedInt32Array
## Bits +X, -X, +Y, -Y, +Z, -Z. A face counts once regardless of neighbor count.
@export var open_side_masks: PackedByteArray

@export var grid_dimensions: Vector3i
@export var max_side_cells: int
@export var wall_checksum: int

func is_compatible(walls: NoxelWallStorage, dimensions: Vector3i, side_limit: int) -> bool:
	return walls != null \
		and grid_dimensions == dimensions \
		and max_side_cells == side_limit \
		and wall_checksum == hash(walls._wallInformation) \
		and cell_to_cluster.size() == dimensions.x * dimensions.y * dimensions.z \
		and cluster_origins.size() == cluster_sides.size() \
		and open_side_masks.size() == cluster_sides.size() \
		and neighbor_offsets.size() == cluster_sides.size() + 1 \
		and neighbor_offsets[cluster_sides.size()] == neighbor_ids.size()

func build(walls: NoxelWallStorage, dimensions: Vector3i, side_limit: int) -> void:
	grid_dimensions = dimensions
	max_side_cells = maxi(1, side_limit)
	wall_checksum = hash(walls._wallInformation)
	var cell_count: int = dimensions.x * dimensions.y * dimensions.z
	var width: int = dimensions.x
	var plane: int = width * dimensions.y
	var wall_bits: PackedByteArray = walls._wallInformation
	cell_to_cluster.resize(cell_count)
	cell_to_cluster.fill(-1)
	cluster_origins.clear()
	cluster_sides.clear()
	neighbor_offsets.clear()
	neighbor_ids.clear()
	open_side_masks.clear()
	
	# Greedy, deterministic partition. Test only the three newly added cube faces
	# when increasing a candidate's side, then mark its cells in one pass.
	for origin: int in cell_count:
		if cell_to_cluster[origin] != -1 or (wall_bits[origin >> 3] & (1 << (origin & 7))) != 0:
			continue
		var x: int = origin % width
		var y: int = (origin / width) % dimensions.y
		var z: int = origin / plane
		var limit: int = mini(max_side_cells, mini(dimensions.x - x, mini(dimensions.y - y, dimensions.z - z)))
		var side: int = 1
		for candidate: int in range(2, limit + 1): # if i did this in programming class, the teachers would probably kill themself
			var edge: int = candidate - 1
			var fits: bool = true
			for dz: int in candidate:
				for dy: int in candidate:
					for dx: int in candidate:
						if dx != edge and dy != edge and dz != edge:
							continue
						var cell: int = origin + dx + dy * width + dz * plane
						if cell_to_cluster[cell] != -1 or (wall_bits[cell >> 3] & (1 << (cell & 7))) != 0:
							fits = false
							break
					if not fits:
						break
				if not fits:
					break
			if not fits:
				break
			side = candidate
		var cluster_id: int = cluster_sides.size()
		cluster_origins.append(origin)
		cluster_sides.append(side)
		for dz: int in side:
			for dy: int in side:
				for dx: int in side:
					cell_to_cluster[origin + dx + dy * width + dz * plane] = cluster_id
	
	_build_neighbors()

func _build_neighbors() -> void:
	var width: int = grid_dimensions.x
	var plane: int = width * grid_dimensions.y
	var cluster_count: int = cluster_sides.size()
	var seen: PackedInt32Array
	seen.resize(cluster_count)
	seen.fill(-1)
	neighbor_offsets.append(0)

	for cluster_id: int in cluster_count:
		var origin: int = cluster_origins[cluster_id]
		var side: int = cluster_sides[cluster_id]
		var x: int = origin % width
		var y: int = (origin / width) % grid_dimensions.y
		var z: int = origin / plane
		var mask: int = 0
		for direction: int in 6:
			if direction == 0 and x + side >= grid_dimensions.x:
				continue
			if direction == 1 and x == 0:
				continue
			if direction == 2 and y + side >= grid_dimensions.y:
				continue
			if direction == 3 and y == 0:
				continue
			if direction == 4 and z + side >= grid_dimensions.z:
				continue
			if direction == 5 and z == 0:
				continue
			
			for v: int in side:
				for u: int in side:
					var adjacent_cell: int
					match direction:
						0: adjacent_cell = origin + side + u * width + v * plane
						1: adjacent_cell = origin - 1 + u * width + v * plane
						2: adjacent_cell = origin + u + side * width + v * plane
						3: adjacent_cell = origin + u - width + v * plane
						4: adjacent_cell = origin + u + v * width + side * plane
						_: adjacent_cell = origin + u + v * width - plane
					var neighbor: int = cell_to_cluster[adjacent_cell]
					if neighbor < 0 or neighbor == cluster_id:
						continue
					mask |= 1 << direction
					if seen[neighbor] != cluster_id:
						seen[neighbor] = cluster_id
						neighbor_ids.append(neighbor)
		open_side_masks.append(mask)
		neighbor_offsets.append(neighbor_ids.size())
