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
func _resetMaps():
	walls = currentNoxelMap.wallBakeData
	var dim : Vector3i = currentNoxelMap.vGridDimensions
	var count := dim.x * dim.y * dim.z
	soundLevel.resize(count)
	emitter.resize(count)
