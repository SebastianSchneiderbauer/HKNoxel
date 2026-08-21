extends Node3D

@onready var meshContainer: Node3D = $meshContainer
@onready var mesh_red: MeshInstance3D = $meshContainer/meshRed
@onready var mesh_green: MeshInstance3D = $meshContainer/meshGreen
@onready var info: Label3D = $meshContainer/info

func _physics_process(delta: float) -> void:
	var cellSize := HKNoxelManager.cellSize
	meshContainer.scale = Vector3(cellSize, cellSize, cellSize)
	
	var result := HKNoxelManager.getNoxelInformation(global_position + Vector3(cellSize/2, cellSize/2, cellSize/2)) # just so we check at the center
	#info.text = str(result)
	
	if result.x == 0:
		info.text = ""
		mesh_red.show()
		mesh_green.hide()
	else:
		info.text = "soundLevel: " + str(result.x) + "\nemitterID: " + str(result.y)
		mesh_red.hide()
		mesh_green.show()
