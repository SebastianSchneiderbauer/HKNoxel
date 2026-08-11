extends Node

var currentNoxelMap
func _exists() -> bool:
	if currentNoxelMap:
		return true
	else:
		return false
func setCurrentNMap(nm, reset : bool = true) -> void:
	currentNoxelMap = nm
	
	if reset:
		_resetMaps()
func removeCurrentNmap():
	currentNoxelMap = null

var walls: NoxelWallStorage
var soundLevel: PackedByteArray
var emitter: PackedByteArray
var dimensions: Vector3i

var activeCellIds: Array[int]

var gridStartPosition: Vector3
var cellCount: int
var cellSize: float

# so everythign works together nicely
func _resetMaps():
	walls = currentNoxelMap.wallBakeData
	dimensions = currentNoxelMap.vGridDimensions
	cellCount = dimensions.x * dimensions.y * dimensions.z
	soundLevel.resize(cellCount) # resize -> everything is 0
	emitter.resize(cellCount)
	gridStartPosition = currentNoxelMap.vGridStartPosition
	cellSize = currentNoxelMap.cell_size
func _indexOf(objectPosition: Vector3) -> int: # ported from the Noxel
	var relativePosition: Vector3 = objectPosition - gridStartPosition
	var voxelPosition: Vector3 = (relativePosition / cellSize).round()
	return int(voxelPosition.x + voxelPosition.y * dimensions.x + voxelPosition.z * dimensions.x * dimensions.y)

# registration for sound emitting
var _free_ids: Array[int] = []
var _active_sources: Array[Node] = []
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
	_active_sources[id] = null
	_free_ids.append(id)
func get_source(id: int) -> Node:
	if id < 0 or id >= _active_sources.size():
		return null
	return _active_sources[id]

func _getNeighbourIndexes(cellIndex: int) -> Array[int]: # this is a abomination and should be banished into the dephs of hell
	# formula x + y * dim.x + z * dim.x * dim.y
	var result : Array[int]
	# x
	if _checkCellIndex(cellIndex + 1):
		result.append(cellIndex + 1)
	if _checkCellIndex(cellIndex - 1):
		result.append(cellIndex - 1)
	# y
	if _checkCellIndex(cellIndex + 1 * dimensions.x):
		result.append(cellIndex + 1 * dimensions.x)
	if _checkCellIndex(cellIndex - 1 * dimensions.x):
		result.append(cellIndex - 1 * dimensions.x)
	# z
	if _checkCellIndex(cellIndex + 1 * dimensions.x * dimensions.y):
		result.append(cellIndex + 1 * dimensions.x * dimensions.y)
	if _checkCellIndex(cellIndex - 1 * dimensions.x * dimensions.y):
		result.append(cellIndex - 1 * dimensions.x * dimensions.y)
	
	return result
func _checkCellIndex(cellIndex: int) -> bool:
	return cellIndex >= 0 and cellIndex < cellCount
## Used for emitting a sound at a position. Decibels is a integer that can take values storable in an unsigned byte. Fails if the emitterId is not valid or the position is outside of the baked NoxelMap
func emitSound(startPosition: Vector3, decibels: int, emitterId: int):
#region safety checks
	# errors
	if emitterId < 0 or emitterId >= 256:
		printerr("emitterID out of range")
		return
	if _free_ids.has(emitterId):
		printerr("emitterID not registered")
		return
	var cellIndex := _indexOf(startPosition)
	if cellIndex >= cellCount:
		printerr("sound is out of this world") # holy
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
	activeCellIds.append(cellIndex)
