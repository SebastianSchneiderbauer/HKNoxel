class_name NoxelWallStorage

extends Resource

@export var _wallInformation : PackedByteArray
@export var _cellCount: int

func _init(arraysize: int = 0) -> void: # because the engine initializes with no parameters, we dont want it resetting our baking
	if arraysize > 0:
		_initializeWallArray(arraysize)

## Used to initialize the array, setting all values to 0 and ensuring it has the correct length
func _initializeWallArray(arraysize : int) -> void : # we get in the amount of cells. We use only one bit per wall
	_cellCount = arraysize
	_wallInformation.resize(ceili(float(arraysize) / 8))

## Used for placing or removing a wall
func updateWall(positionId : int, isWall : bool) -> void :
	if positionId < 0 or positionId >= _cellCount:
		return
	
	var location := _convertPosId(positionId)
	var byteValue := _wallInformation[location.x]
	_wallInformation[location.x] = _set_bit(byteValue, location.y, isWall)

## Used for checking if something is a wall
func isWall(positionId : int) -> bool:
	if positionId < 0 or positionId >= _cellCount:
		return false
	
	var location := _convertPosId(positionId)
	var byteValue := _wallInformation[location.x]
	return _get_bit(byteValue, location.y)

## Used internally since we only use one bit per wall
func _convertPosId(positionId: int) -> Vector2i:
	var arrayID := positionId / 8
	var bitID := positionId % 8
	return Vector2i(arrayID, bitID)
func _get_bit(byte_value: int, bit_index: int) -> bool:
	return (byte_value & (1 << bit_index)) != 0
func _set_bit(byte_value: int, bit_index: int, value: bool) -> int:
	if value:
		return byte_value | (1 << bit_index)
	else:
		return byte_value & ~(1 << bit_index)
