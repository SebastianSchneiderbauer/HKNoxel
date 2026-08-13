extends Node3D

@onready var meshContainer: Node3D = $meshContainer

func _physics_process(delta: float) -> void:
	var cellSize := HKNoxelManager.cellSize
	meshContainer.scale = Vector3(cellSize, cellSize, cellSize)
	
	var visible : bool = HKNoxelManager.get
