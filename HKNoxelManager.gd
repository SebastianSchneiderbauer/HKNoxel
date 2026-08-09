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

func getCurrentNMap():
	if not _exists():
		return
	
	return currentNoxelMap

var walls: PackedByteArray
var soundLevel: PackedByteArray
var emitter: PackedByteArray
func _resetMaps():
	currentNoxelMap.wallBakeData
