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

var _free_ids: Array[int] = []
var _active_sources: Array[Node] = []
var _freeQueue: PackedByteArray = []
var _freeQueueDetector: PackedByteArray

var TESTID: int = -1
var _isDebug: bool = false
var _debug_labels: Array[Label3D] = []


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
	_clear_debug_labels()


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
		var deduction_per_cell: float = _sideDeductions[clusters.open_side_masks[source_id]]
		if deduction_per_cell == 0.0:
			continue
		for edge: int in range(clusters.neighbor_offsets[source_id], clusters.neighbor_offsets[source_id + 1]):
			var destination_id: int = clusters.neighbor_ids[edge]
			var candidate: float = _soundLevelSnapshot[i] - deduction_per_cell * clusters.cluster_sides[destination_id]
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
