extends Node
# NOTE: these comments looks HELLA ai generated, but im lwk too lazy, so fuck you
var currentNoxelMap
func _exists() -> bool:
	if currentNoxelMap:
		return true
	else:
		return false
func setCurrentNMap(nm, reset : bool = true) -> void:
	print("reveived NOXELMAP update. update: " + str(reset))
	currentNoxelMap = nm
	
	if reset:
		_resetMaps()
func removeCurrentNmap():
	currentNoxelMap = null

var walls: NoxelWallStorage
var soundLevel: PackedFloat32Array
var emitter: PackedByteArray
var dimensions: Vector3i

var activeCellIds: Array[int]

var gridStartPosition: Vector3
var cellCount: int
var cellSize: float

# so everythign works together nicely
func _resetMaps():
	walls = currentNoxelMap.wallBakeData
	print(walls._cellCount)
	dimensions = currentNoxelMap.vGridDimensions
	print(dimensions)
	cellCount = dimensions.x * dimensions.y * dimensions.z
	soundLevel.resize(cellCount)
	soundLevel.fill(0) # theoredicly resize already does this, however not if the size is the exact same
	emitter.resize(cellCount)
	emitter.fill(0) # same as above
	gridStartPosition = currentNoxelMap.vGridStartPosition
	cellSize = currentNoxelMap.cell_size
func _indexOf(objectPosition: Vector3) -> int: # ported from the Noxel
	var relativePosition: Vector3 = objectPosition - gridStartPosition
	var voxelPosition: Vector3 = (relativePosition / cellSize).floor()
	return int(voxelPosition.x + voxelPosition.y * dimensions.x + voxelPosition.z * dimensions.x * dimensions.y)
func _positionOf(index: int) -> Vector3:
	if dimensions == Vector3i.ZERO:
		printerr("cannot get position if dimensions were not specified")
		return Vector3.ZERO
	
	var width := dimensions.x
	var height := dimensions.y
	
	var x := index % width
	var y := (index / width) % height
	var z := index / (width * height)
	
	return gridStartPosition + Vector3(x, y, z) * cellSize

# registration for sound emitting
var _free_ids: Array[int] = []
var _active_sources: Array[Node] = []
var _freeQueue: PackedByteArray = []
var _freeQueueDetector: PackedByteArray

func _ready() -> void:
	_active_sources.resize(256) # hardcoding is fine here for once
	for i in 256:
		_free_ids.append(i)
func register_source(source: Node) -> int:
	if _free_ids.is_empty():
		push_error("HKNoxel: id pool exhausted")
		return -1
	var id: int = _free_ids.pop_back()
	_active_sources[id] = source
	return id
func free_source(id: int) -> void:
	if not _freeQueue.has(id): 
		_freeQueue.append(id) # we stage for deletion, since sound of that emitter could still be active and reassigned to other emitters in the worst case
func get_source(id: int) -> Node:
	if id < 0 or id >= _active_sources.size():
		return null
	return _active_sources[id]

func _getFreeNeighbourIndexes(cellIndex: int) -> Array[int]: # this is a abomination and should be banished into the dephs of hell
	# formula x + y * dim.x + z * dim.x * dim.y
	var result : Array[int]
	var x := cellIndex % dimensions.x
	var y := (cellIndex / dimensions.x) % dimensions.y
	
	# x
	if x + 1 < dimensions.x and _checkCellIndex(cellIndex + 1):
		result.append(cellIndex + 1)
	if x - 1 >= 0 and _checkCellIndex(cellIndex - 1):
		result.append(cellIndex - 1)
	
	# y
	if y + 1 < dimensions.y and _checkCellIndex(cellIndex + 1 * dimensions.x):
		result.append(cellIndex + 1 * dimensions.x)
	if y - 1 >= 0 and _checkCellIndex(cellIndex - 1 * dimensions.x):
		result.append(cellIndex - 1 * dimensions.x)
	
	# z
	if _checkCellIndex(cellIndex + 1 * dimensions.x * dimensions.y):
		result.append(cellIndex + 1 * dimensions.x * dimensions.y)
	if _checkCellIndex(cellIndex - 1 * dimensions.x * dimensions.y):
		result.append(cellIndex - 1 * dimensions.x * dimensions.y)
	
	return result
func _checkCellIndex(cellIndex: int) -> bool:
	return cellIndex >= 0 and cellIndex < cellCount and not walls.isWall(cellIndex)
const SOUND_FLOOR = 0.1
## Used for emitting a sound at a position. Decibels is a integer that can take values storable in an unsigned byte. Fails if the emitterId is not valid or the position is outside of the baked NoxelMap
func emitSound(startPosition: Vector3, decibels: int, emitterId: int):
#region safety checks
	# errors
	if decibels < SOUND_FLOOR:
		printerr("too quiet")
		return
	if _free_ids.has(emitterId):
		printerr("emitterID not registered")
		return
	var cellIndex := _indexOf(startPosition)
	if cellIndex < 0 or cellIndex >= cellCount:
		printerr("sound is out of this world: " + str(cellIndex) + " / " + str(cellCount)) # holy wording
		return
	if walls.isWall(cellIndex):
		printerr("sound cannot be started in wall")
		return
	
	# warning(s)
	if decibels < 0 or decibels > 255:
		var snapvalue := clamp(decibels, 0, 255)
		print("WARNING: snapped decibel value of " + str(decibels) + " to " + str(snapvalue))
		decibels = snapvalue
	
	var cellsCurrentSound = soundLevel[cellIndex]
	if cellsCurrentSound > decibels:
		return # no need in puttin a sound here that is weaker than the existing sound
#endregion
	# safety checks are done now, we can assume everything is safe (now watch me completely fuck it up)
	soundLevel[cellIndex] = decibels
	emitter[cellIndex] = emitterId
	if not activeCellIds.has(cellIndex):
		activeCellIds.append(cellIndex)
		print("added sound as new active cell")

## Lets you check the sound level of a cell, as well as the emitters ID, auto-returns Vector2.ZERO on bad input
func getNoxelInformation(wantedPosition: Vector3) -> Vector2 :
	var posIndex := _indexOf(wantedPosition)
	if not _checkCellIndex(posIndex):
		return Vector2.ZERO
	
	return Vector2(soundLevel[posIndex], emitter[posIndex])

const CONFINEMENT_DEDUCTION : float = 0.4
const CONSTANT_DEDUCTION_MULTIPLIER : float = 0.95 
var TESTID
var _isDebug : bool = false
func setDebugMode(debug: bool):
	if _isDebug and not debug:
		_clear_debug_labels()
	_isDebug = debug
func _physics_process(delta: float) -> void:
	# we currently would only reach a sound-speed of 60 m/s, nowhere close to the 343 m/s of the actual speed of sound (also dependent on the cellsize)
	# 2 options, either ignore it or simulate multiple spreads per tick (5.7 btw, fuck, just make it 6 atp.)
	if Input.is_action_just_pressed("ui_undo") and _isDebug:
		print("Prepping sim")
		if not TESTID:
			TESTID = register_source(self)
		emitSound(get_tree().get_first_node_in_group("player").global_position + Vector3.UP, 5, TESTID) # this assumes you have a player in a group called player
	
	if Input.is_action_just_pressed("ui_redo") or not _isDebug: # GIG, wie geil ist Dustin
		simulateSound(_isDebug)
func simulateSound(generateDebug: bool = false) -> void:
	var debug_start_usec := Time.get_ticks_usec() if generateDebug else 0
	
	# reset freeing detector Array
	_freeQueueDetector.resize(256)
	_freeQueueDetector.fill(0)
	
	# only the currently active cells can change this tick, so we only need their pre-tick values,
	# not a copy of the whole (potentially huge) grid
	var soundLevelSnapshot: Dictionary = {}
	for cellID in activeCellIds:
		soundLevelSnapshot[cellID] = soundLevel[cellID]
	var cellsToActivate: Array[int]
	var cellsToDeactivate: Array[int]
	for indexCounter in activeCellIds.size():
		var cellID = activeCellIds[indexCounter]
		# spreading logic
		var emitterID = emitter[cellID]
		var neighbourCellIDs = _getFreeNeighbourIndexes(cellID)
		var freeNeighbourCount = neighbourCellIDs.size()
		var currentSoundLevel = soundLevelSnapshot[cellID] # pre tick data that was not edited by another cell
		var newSoundLevel = currentSoundLevel - (float(freeNeighbourCount) / 6) * CONFINEMENT_DEDUCTION
		if newSoundLevel < SOUND_FLOOR: # we DO NOT have to pass on a sound that would make a cell delete itself again
			soundLevel[cellID] = 0
			emitter[cellID] = 0
			cellsToDeactivate.append(indexCounter)
			continue
		for neighbourCellID in neighbourCellIDs:
			var neighbourSoundLevel = soundLevel[neighbourCellID]
			if newSoundLevel <= neighbourSoundLevel:
				continue
			
			emitter[neighbourCellID] = emitterID
			soundLevel[neighbourCellID] = newSoundLevel
			if neighbourSoundLevel == 0: # cell was previously not active
				cellsToActivate.append(neighbourCellID)
		
		# percentage decrease of each cell
		if currentSoundLevel * CONSTANT_DEDUCTION_MULTIPLIER >= SOUND_FLOOR:
			soundLevel[cellID] = currentSoundLevel * CONSTANT_DEDUCTION_MULTIPLIER
		else:
			soundLevel[cellID] = 0
			emitter[cellID] = 0
			cellsToDeactivate.append(indexCounter)
		
		# deletion logic
		_freeQueueDetector[emitterID] = 1
	if generateDebug:
		print("went over " + str(activeCellIds.size()) + " cells")
	
	# adding all new cells
	for cellID in cellsToActivate: # we cannot have duplicates here, since they are not inserted into cellsToActivate
		activeCellIds.append(cellID)
	if generateDebug:
		print("added over " + str(cellsToActivate.size()) + " active cells")
	
	# removin deleted cells
	if generateDebug:
		print(cellsToDeactivate.size())
	if cellsToDeactivate.size() != 0:
		cellsToDeactivate.sort()
		cellsToDeactivate.reverse()
	for cellIndex in cellsToDeactivate:
		# swap delete for performence
		var lastIndex = activeCellIds.size() - 1
		var storage = activeCellIds[lastIndex]
		activeCellIds[lastIndex] = activeCellIds[cellIndex]
		activeCellIds[cellIndex] = storage
		activeCellIds.pop_back()
	if generateDebug:
		print("removed over " + str(cellsToDeactivate.size()) + " active cells")
	
	# deletion logic for emitterIds
	var stillPending: PackedByteArray = []
	for queuedId in _freeQueue:
		if _freeQueueDetector[queuedId] == 0:
			_active_sources[queuedId] = null
			_free_ids.append(queuedId)
		else:
			stillPending.append(queuedId)
	if Input.is_action_just_pressed("c"):
		print(_freeQueueDetector)
	_freeQueue = stillPending

	
	# if we want debugging visuals, create them
	if generateDebug:
		var elapsed_usec := Time.get_ticks_usec() - debug_start_usec
		print("simulateSound took " + str(elapsed_usec / 1000.0) + " ms (excluding debug label placement)")
		print("now generating debug")
		debug_visualize_active_cells()

# debugging stuff, not needed afterwards
var _debug_labels: Array[Label3D] = []
func debug_visualize_active_cells() -> void:#
	_clear_debug_labels()
	for cellID in activeCellIds:
		var label := Label3D.new()
		label.text = "%.1f" % soundLevel[cellID]
		label.position = _positionOf(cellID) + Vector3(cellSize/2, cellSize/2, cellSize/2)
		#label.pixel_size = 0.01  # tune for readability at your cell scale
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		_debug_labels.append(label)
func _clear_debug_labels() -> void:
	for label in _debug_labels:
		label.queue_free()
	_debug_labels.clear()
