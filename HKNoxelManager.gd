extends Node

const SOUND_FLOOR: float = 0.1
const CONFINEMENT_DEDUCTION: float = 0.4
const CONSTANT_DEDUCTION_MULTIPLIER: float = 0.95

var currentNoxelMap
var walls: NoxelWallStorage
var clusters: NoxelClusterStorage
var dimensions: Vector3i
var gridStartPosition: Vector3
var cellSize: float
var cellCount: int

# Sound is stored once per free cluster, while position and wall queries still
# resolve through the fine grid. Newly activated clusters run on the next tick.
var soundLevel: PackedFloat32Array
var emitter: PackedByteArray
var activeClusterIds: Array[int]
var _activeFlags: PackedByteArray
var _soundLevelSnapshot: PackedFloat32Array
var _emitterSnapshot: PackedByteArray
var _cachedWallRevision: int = -1
var _cachedMaxSideCells: int = -1
var _sideDeductions: PackedFloat32Array
var _clusterTravelDeductions: PackedFloat32Array

var _free_ids: Array[int] = []
var _active_sources: Array[Node] = []
var _freeQueue: PackedByteArray = []
var _freeQueueDetector: PackedByteArray

var TESTID: int = -1
var _isDebug: bool = false
var _debug_labels: Array[Label3D] = []
var _showClusterDebug: bool = false
var _cluster_debug_mesh: MultiMeshInstance3D
var _debug_console: Node


func _exists() -> bool:
	return currentNoxelMap != null


func setCurrentNMap(nm, reset: bool = true) -> void:
	currentNoxelMap = nm
	if reset:
		_resetMaps()
	else:
		_clearGrid()


func removeCurrentNmap() -> void:
	currentNoxelMap = null
	_clearGrid()


func _clearGrid() -> void:
	# Once the field is discarded, staged source IDs can be reused safely.
	for queued_id: int in _freeQueue:
		if queued_id < _active_sources.size():
			_active_sources[queued_id] = null
			_free_ids.append(queued_id)
	_freeQueue.clear()
	walls = null
	clusters = null
	dimensions = Vector3i.ZERO
	cellCount = 0
	soundLevel.clear()
	emitter.clear()
	_activeFlags.clear()
	activeClusterIds.clear()
	_cachedWallRevision = -1
	_cachedMaxSideCells = -1
	_clear_debug_labels()
	_clear_cluster_visualization()


func _resetMaps() -> void:
	_clearGrid()
	walls = currentNoxelMap.wallBakeData
	dimensions = currentNoxelMap.vGridDimensions
	if walls == null or dimensions.x <= 0 or dimensions.y <= 0 or dimensions.z <= 0:
		push_error("HKNoxel: bake the wall grid before using the map")
		return
	cellCount = dimensions.x * dimensions.y * dimensions.z
	if walls._cellCount != cellCount:
		push_error("HKNoxel: wall bake dimensions do not match the map")
		_clearGrid()
		return
	gridStartPosition = currentNoxelMap.vGridStartPosition
	cellSize = currentNoxelMap.cell_size
	if cellSize <= 0.0:
		push_error("HKNoxel: cell_size must be greater than zero")
		_clearGrid()
		return
	_rebuildClusterCache()


func _rebuildClusterCache() -> void:
	var max_side_cells: int = maxi(1, floori(currentNoxelMap.max_cluster_width / cellSize))
	var baked: NoxelClusterStorage = currentNoxelMap.clusterBakeData
	if baked != null and baked.is_compatible(walls, dimensions, max_side_cells):
		clusters = baked
	else:
		clusters = NoxelClusterStorage.new()
		clusters.build(walls, dimensions, max_side_cells)
		# Older wall-only bakes and runtime wall changes can still run. An editor
		# rebake is needed to serialize the generated cluster data in the scene.
		if not Engine.is_editor_hint():
			currentNoxelMap.clusterBakeData = clusters
	var cluster_count: int = clusters.cluster_sides.size()
	soundLevel.resize(cluster_count)
	soundLevel.fill(0.0)
	emitter.resize(cluster_count)
	emitter.fill(0)
	_activeFlags.resize(cluster_count)
	_activeFlags.fill(0)
	activeClusterIds.clear()
	_cachedWallRevision = walls.revision
	_cachedMaxSideCells = max_side_cells
	_sideDeductions.resize(64)
	for mask: int in 64:
		var side_count: int = 0
		for direction: int in 6:
			if mask & (1 << direction):
				side_count += 1
		_sideDeductions[mask] = float(side_count) * CONFINEMENT_DEDUCTION / 6.0
	_clusterTravelDeductions.resize(cluster_count)
	for cluster_id: int in cluster_count:
		# A cube's internal free steps used to be individual noxels. Approximate
		# those steps at the six-neighbor rate, then charge its exposed faces.
		var internal_steps: int = clusters.cluster_sides[cluster_id] - 1
		_clusterTravelDeductions[cluster_id] = float(internal_steps) * CONFINEMENT_DEDUCTION + _sideDeductions[clusters.open_side_masks[cluster_id]]
	_clear_debug_labels()
	if _showClusterDebug:
		_build_cluster_visualization()


func _indexOf(objectPosition: Vector3) -> int:
	if cellCount == 0:
		return -1
	var fine_position: Vector3 = ((objectPosition - gridStartPosition) / cellSize).floor()
	var x: int = int(fine_position.x)
	var y: int = int(fine_position.y)
	var z: int = int(fine_position.z)
	if x < 0 or x >= dimensions.x or y < 0 or y >= dimensions.y or z < 0 or z >= dimensions.z:
		return -1
	return x + y * dimensions.x + z * dimensions.x * dimensions.y


func _positionOf(cluster_id: int) -> Vector3:
	var origin: int = clusters.cluster_origins[cluster_id]
	var side: int = clusters.cluster_sides[cluster_id]
	var x: int = origin % dimensions.x
	var y: int = (origin / dimensions.x) % dimensions.y
	var z: int = origin / (dimensions.x * dimensions.y)
	return gridStartPosition + (Vector3(x, y, z) + Vector3.ONE * float(side) * 0.5) * cellSize


func _ready() -> void:
	_active_sources.resize(256)
	for i: int in 256:
		_free_ids.append(i)
	call_deferred("_register_debug_command")


func _exit_tree() -> void:
	if is_instance_valid(_debug_console):
		_debug_console.call("unregister_command", "debugchunks")
	_clear_cluster_visualization()


func _register_debug_command() -> void:
	_debug_console = get_node_or_null("/root/HKConsole")
	if _debug_console and _debug_console.has_method("register_command"):
		_debug_console.call("register_command", "debugchunks", Callable(self, "_toggle_cluster_visualization"), true, true)


func _toggle_cluster_visualization() -> void:
	setClusterVisualization(not _showClusterDebug)
	var message: String = "Sound chunks: " + ("visible" if _showClusterDebug else "hidden")
	if _showClusterDebug and clusters == null:
		message += " (waiting for a baked map)"
	if is_instance_valid(_debug_console) and _debug_console.has_method("logInfo"):
		_debug_console.call("logInfo", message)
	else:
		print(message)


func setClusterVisualization(visible: bool) -> void:
	_showClusterDebug = visible
	if visible:
		_build_cluster_visualization()
	else:
		_clear_cluster_visualization()


func _build_cluster_visualization() -> void:
	_clear_cluster_visualization()
	if clusters == null or clusters.cluster_sides.is_empty():
		return

	# A unit wire cube is scaled and placed once per cluster by a MultiMesh.
	# Lines make the partition visible without hiding the level geometry.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	var wire_cube := ImmediateMesh.new()
	wire_cube.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var corners := [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5),
	]
	var edges := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]
	for corner_index: int in edges:
		wire_cube.surface_add_vertex(corners[corner_index])
	wire_cube.surface_end()

	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = wire_cube
	instances.instance_count = clusters.cluster_sides.size()
	var max_side: int = maxi(1, clusters.max_side_cells)
	for cluster_id: int in clusters.cluster_sides.size():
		var side: int = clusters.cluster_sides[cluster_id]
		var width: float = float(side) * cellSize * 0.98
		instances.set_instance_transform(cluster_id, Transform3D(Basis().scaled(Vector3.ONE * width), _positionOf(cluster_id)))
		var fraction: float = float(side - 1) / float(maxi(1, max_side - 1))
		instances.set_instance_color(cluster_id, Color.from_hsv(0.55 - 0.50 * fraction, 0.9, 1.0))

	_cluster_debug_mesh = MultiMeshInstance3D.new()
	_cluster_debug_mesh.name = "HKNoxelClusterDebug"
	_cluster_debug_mesh.multimesh = instances
	_cluster_debug_mesh.custom_aabb = AABB(gridStartPosition, Vector3(dimensions) * cellSize)
	add_child(_cluster_debug_mesh)


func _clear_cluster_visualization() -> void:
	if is_instance_valid(_cluster_debug_mesh):
		_cluster_debug_mesh.queue_free()
	_cluster_debug_mesh = null


func register_source(source: Node) -> int:
	if _free_ids.is_empty():
		push_error("HKNoxel: id pool exhausted")
		return -1
	var id: int = _free_ids.pop_back()
	_active_sources[id] = source
	return id


func free_source(id: int) -> void:
	if id < 0 or id >= _active_sources.size() or _active_sources[id] == null:
		return
	if clusters == null or activeClusterIds.is_empty():
		_active_sources[id] = null
		_free_ids.append(id)
		return
	if not _freeQueue.has(id):
		_freeQueue.append(id)


func get_source(id: int) -> Node:
	if id < 0 or id >= _active_sources.size():
		return null
	return _active_sources[id]


## Emits into the cluster containing startPosition. "decibels" is a game level,
## not an acoustic decibel measurement.
func emitSound(startPosition: Vector3, decibels: int, emitterId: int) -> void:
	if decibels < SOUND_FLOOR:
		printerr("too quiet")
		return
	if get_source(emitterId) == null:
		printerr("emitterID not registered")
		return
	var cell_index: int = _indexOf(startPosition)
	if cell_index < 0:
		printerr("sound is out of this world")
		return
	var cluster_id: int = clusters.cell_to_cluster[cell_index]
	if cluster_id < 0:
		printerr("sound cannot be started in wall")
		return
	if decibels > 255:
		print("WARNING: snapped decibel value of " + str(decibels) + " to 255")
		decibels = 255
	if soundLevel[cluster_id] > decibels:
		return
	soundLevel[cluster_id] = decibels
	emitter[cluster_id] = emitterId
	if _activeFlags[cluster_id] == 0:
		_activeFlags[cluster_id] = 1
		activeClusterIds.append(cluster_id)


## Returns the cluster sound level and emitter ID at a fine-grid position.
func getNoxelInformation(wantedPosition: Vector3) -> Vector2:
	var cell_index: int = _indexOf(wantedPosition)
	if cell_index < 0:
		return Vector2.ZERO
	var cluster_id: int = clusters.cell_to_cluster[cell_index]
	if cluster_id < 0:
		return Vector2.ZERO
	return Vector2(soundLevel[cluster_id], emitter[cluster_id])


func setDebugMode(debug: bool) -> void:
	if _isDebug and not debug:
		_clear_debug_labels()
	_isDebug = debug


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_undo") and _isDebug:
		if TESTID < 0:
			TESTID = register_source(self)
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player:
			emitSound(player.global_position + Vector3.UP, 10, TESTID)
	if Input.is_action_just_pressed("ui_redo") or not _isDebug:
		simulateSound(_isDebug)


func simulateSound(generateDebug: bool = false) -> void:
	var debug_start_usec: int = Time.get_ticks_usec() if generateDebug else 0
	if walls == null or clusters == null:
		return
	if _cachedWallRevision != walls.revision or _cachedMaxSideCells != maxi(1, floori(currentNoxelMap.max_cluster_width / cellSize)):
		_rebuildClusterCache()

	var active_count: int = activeClusterIds.size()
	if _soundLevelSnapshot.size() < active_count:
		var capacity: int = maxi(active_count, maxi(1, _soundLevelSnapshot.size() * 2))
		_soundLevelSnapshot.resize(capacity)
		_emitterSnapshot.resize(capacity)
	for i: int in active_count:
		var cluster_id: int = activeClusterIds[i]
		_soundLevelSnapshot[i] = soundLevel[cluster_id]
		_emitterSnapshot[i] = emitter[cluster_id]

	# Decay the old field first. Incoming sound then competes with the decayed
	# value, so processing order cannot erase a stronger arrival in this tick.
	for i: int in active_count:
		var cluster_id: int = activeClusterIds[i]
		var decayed: float = _soundLevelSnapshot[i] * CONSTANT_DEDUCTION_MULTIPLIER
		if decayed >= SOUND_FLOOR:
			soundLevel[cluster_id] = decayed
		else:
			soundLevel[cluster_id] = 0.0
			emitter[cluster_id] = 0

	for i: int in active_count:
		var source_id: int = activeClusterIds[i]
		var travel_deduction: float = _clusterTravelDeductions[source_id]
		if travel_deduction == 0.0:
			continue
		for edge: int in range(clusters.neighbor_offsets[source_id], clusters.neighbor_offsets[source_id + 1]):
			var destination_id: int = clusters.neighbor_ids[edge]
			var candidate: float = _soundLevelSnapshot[i] - travel_deduction
			if candidate < SOUND_FLOOR or candidate <= soundLevel[destination_id]:
				continue
			soundLevel[destination_id] = candidate
			emitter[destination_id] = _emitterSnapshot[i]
			if _activeFlags[destination_id] == 0:
				_activeFlags[destination_id] = 1
				activeClusterIds.append(destination_id)

	# Only the old portion may have gone inactive. Swap removal keeps the list
	# compact without sorting or shifting a large active cloud.
	for i: int in range(active_count - 1, -1, -1):
		var cluster_id: int = activeClusterIds[i]
		if soundLevel[cluster_id] != 0.0:
			continue
		_activeFlags[cluster_id] = 0
		activeClusterIds[i] = activeClusterIds[activeClusterIds.size() - 1]
		activeClusterIds.pop_back()

	_freeQueueDetector.resize(256)
	_freeQueueDetector.fill(0)
	for cluster_id: int in activeClusterIds:
		_freeQueueDetector[emitter[cluster_id]] = 1
	var still_pending: PackedByteArray
	for queued_id: int in _freeQueue:
		if _freeQueueDetector[queued_id] == 0:
			_active_sources[queued_id] = null
			_free_ids.append(queued_id)
		else:
			still_pending.append(queued_id)
	_freeQueue = still_pending

	if generateDebug:
		print("simulateSound processed " + str(active_count) + " clusters in " + str((Time.get_ticks_usec() - debug_start_usec) / 1000.0) + " ms")
		debug_visualize_active_cells()


func debug_visualize_active_cells() -> void:
	_clear_debug_labels()
	for cluster_id: int in activeClusterIds:
		var label := Label3D.new()
		label.text = "%.1f" % soundLevel[cluster_id]
		label.position = _positionOf(cluster_id)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		_debug_labels.append(label)


func _clear_debug_labels() -> void:
	for label: Label3D in _debug_labels:
		label.queue_free()
	_debug_labels.clear()
