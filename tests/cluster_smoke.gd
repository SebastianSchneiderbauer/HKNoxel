extends SceneTree

class FakeMap extends RefCounted:
	var vGridDimensions: Vector3i
	var vGridStartPosition: Vector3
	var cell_size: float
	var max_cluster_width: float
	var wallBakeData: NoxelWallStorage
	var clusterBakeData: NoxelClusterStorage

var failures: int = 0
var ran: bool = false


func _process(_delta: float) -> bool:
	if ran:
		return false
	ran = true
	_test_open_cubes()
	_test_mixed_sizes()
	_test_walls_and_faces()
	_test_serialized_bake()
	_test_map_script()
	_test_fast_open_propagation()
	_benchmark_open_grid()
	if failures == 0:
		print("HKNoxel cluster smoke tests passed")
	quit(1 if failures > 0 else 0)
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_walls(dimensions: Vector3i) -> NoxelWallStorage:
	return NoxelWallStorage.new(dimensions.x * dimensions.y * dimensions.z)


func _test_open_cubes() -> void:
	var dimensions := Vector3i(15, 5, 5)
	var storage := NoxelClusterStorage.new()
	storage.build(_make_walls(dimensions), dimensions, 5)
	_expect(storage.cluster_sides.size() == 3, "15x5x5 open space should become three cubes")
	for side: int in storage.cluster_sides:
		_expect(side == 5, "every open cube should have side 5")
	_expect(storage.neighbor_offsets == PackedInt32Array([0, 1, 3, 4]), "three cubes should form a chain")
	_expect(storage.open_side_masks[0] == 1, "first cube should expose only +X")
	_expect(storage.open_side_masks[1] == 3, "middle cube should expose +X and -X")
	_expect(storage.open_side_masks[2] == 2, "last cube should expose only -X")


func _test_walls_and_faces() -> void:
	var dimensions := Vector3i(5, 3, 1)
	var walls := _make_walls(dimensions)
	for y: int in dimensions.y:
		walls.updateWall(2 + y * dimensions.x, true)
	var storage := NoxelClusterStorage.new()
	storage.build(walls, dimensions, 5)
	for y: int in dimensions.y:
		_expect(storage.cell_to_cluster[2 + y * dimensions.x] == -1, "wall must not belong to a cluster")
	for cluster_id: int in storage.cluster_sides.size():
		var origin: int = storage.cluster_origins[cluster_id]
		var on_left: bool = origin % dimensions.x < 2
		for edge: int in range(storage.neighbor_offsets[cluster_id], storage.neighbor_offsets[cluster_id + 1]):
			var other_origin: int = storage.cluster_origins[storage.neighbor_ids[edge]]
			_expect((other_origin % dimensions.x < 2) == on_left, "sound must not cross the wall barrier")


func _test_mixed_sizes() -> void:
	var dimensions := Vector3i(7, 5, 5)
	var storage := NoxelClusterStorage.new()
	storage.build(_make_walls(dimensions), dimensions, 5)
	var large: int = storage.cell_to_cluster[0]
	var small: int = storage.cell_to_cluster[5]
	_expect(storage.cluster_sides[large] == 5, "open region should use the five-cell cube")
	_expect(storage.cluster_sides[small] == 2, "remaining strip should fit a two-cell cube")
	var connected: bool = false
	for edge: int in range(storage.neighbor_offsets[large], storage.neighbor_offsets[large + 1]):
		if storage.neighbor_ids[edge] == small:
			connected = true
	_expect(connected, "different-sized cubes sharing a face must connect")
	_expect(storage.open_side_masks[large] == 1, "many neighbors on +X must count as one open side")


func _test_serialized_bake() -> void:
	var dimensions := Vector3i(7, 5, 5)
	var walls := _make_walls(dimensions)
	var storage := NoxelClusterStorage.new()
	storage.build(walls, dimensions, 5)
	var path: String = "user://hknoxel_cluster_smoke.tres"
	var saved: Error = ResourceSaver.save(storage, path)
	_expect(saved == OK, "cluster bake should save as a Resource")
	if saved != OK:
		return
	var reloaded: NoxelClusterStorage = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(reloaded != null and reloaded.is_compatible(walls, dimensions, 5), "reloaded cluster bake should remain compatible")
	if reloaded:
		_expect(reloaded.neighbor_ids == storage.neighbor_ids, "serialized neighbor graph should survive reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_map_script() -> void:
	var script: GDScript = ResourceLoader.load("res://addons/HKNoxel/HKNoxel.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(script != null and script.can_instantiate(), "NoxelMap should compile with the cluster bake field")


func _test_fast_open_propagation() -> void:
	var manager: Node = root.get_node_or_null("HKNoxelManager")
	if manager == null:
		_expect(false, "project HKNoxelManager autoload is required")
		return
	var dimensions := Vector3i(15, 5, 5)
	var map := FakeMap.new()
	map.vGridDimensions = dimensions
	map.vGridStartPosition = Vector3.ZERO
	map.cell_size = 1.0
	map.max_cluster_width = 5.0
	map.wallBakeData = _make_walls(dimensions)
	map.clusterBakeData = NoxelClusterStorage.new()
	map.clusterBakeData.build(map.wallBakeData, dimensions, 5)
	manager.setCurrentNMap(map)
	var source_id: int = manager.register_source(manager)
	manager.emitSound(Vector3(0.5, 0.5, 0.5), 15, source_id)
	manager.simulateSound()
	var next_level: float = manager.getNoxelInformation(Vector3(7.5, 2.5, 2.5)).x
	_expect(is_equal_approx(next_level, 15.0 - 5.0 * 0.4 / 6.0), "large destination should charge five fine-cell steps")
	_expect(manager.getNoxelInformation(Vector3(12.5, 2.5, 2.5)).x == 0.0, "sound must not cross two edges in one tick")
	manager.simulateSound()
	_expect(manager.getNoxelInformation(Vector3(12.5, 2.5, 2.5)).x > 0.0, "sound should reach the third large cube in two ticks")
	map.wallBakeData.updateWall(7 + 2 * dimensions.x + 2 * dimensions.x * dimensions.y, true)
	manager.simulateSound()
	_expect(manager.activeClusterIds.is_empty(), "changing a wall should rebuild clusters and clear old sound")
	_expect(manager.getNoxelInformation(Vector3(7.5, 2.5, 2.5)) == Vector2.ZERO, "new wall should block its exact fine position")
	manager.free_source(source_id)
	manager.removeCurrentNmap()


func _benchmark_open_grid() -> void:
	var manager: Node = root.get_node_or_null("HKNoxelManager")
	if manager == null:
		return
	var dimensions := Vector3i(50, 50, 50)
	var map := FakeMap.new()
	map.vGridDimensions = dimensions
	map.vGridStartPosition = Vector3.ZERO
	map.cell_size = 1.0
	map.max_cluster_width = 5.0
	map.wallBakeData = _make_walls(dimensions)
	map.clusterBakeData = NoxelClusterStorage.new()
	var bake_start: int = Time.get_ticks_usec()
	map.clusterBakeData.build(map.wallBakeData, dimensions, 5)
	var bake_ms: float = float(Time.get_ticks_usec() - bake_start) / 1000.0
	_expect(map.clusterBakeData.cluster_sides.size() == 1000, "50x50x50 open cells should become 1000 clusters")
	manager.setCurrentNMap(map)
	var source_id: int = manager.register_source(manager)
	manager.emitSound(Vector3(25.5, 25.5, 25.5), 15, source_id)
	var peak_active: int = 0
	var slowest_tick_ms: float = 0.0
	for tick: int in 30:
		var tick_start: int = Time.get_ticks_usec()
		manager.simulateSound()
		slowest_tick_ms = maxf(slowest_tick_ms, float(Time.get_ticks_usec() - tick_start) / 1000.0)
		peak_active = maxi(peak_active, manager.activeClusterIds.size())
	print("Open-grid sample: 125000 cells -> 1000 clusters; bake %.1f ms; peak %d active; slowest tick %.3f ms" % [bake_ms, peak_active, slowest_tick_ms])
	manager.free_source(source_id)
	manager.removeCurrentNmap()
