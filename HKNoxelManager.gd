extends Node

var currentNoxelMap
func _exists() -> bool:
	if currentNoxelMap:
		return true
	else:
		return false

func setCurrentNMap(nm) -> void:
	currentNoxelMap = nm

func getCurrentNMap():
	if not _exists():
		return
	
	return currentNoxelMap
