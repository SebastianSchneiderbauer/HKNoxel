extends Node3D

@onready var meshContainer: Node3D = $meshContainer
@onready var mesh_red: MeshInstance3D = $meshContainer/meshRed
@onready var mesh_green: MeshInstance3D = $meshContainer/meshGreen
@onready var info: Label3D = $meshContainer/info

func _physics_process(delta: float) -> void:
	var cellSize := HKNoxelManager.cellSize
	meshContainer.scale = Vector3(cellSize, cellSize, cellSize)
	
	# there are 2 ways of getting data about a specific position, either .getNoxelInformation() as below, or simply .getSound()
	var result := HKNoxelManager.getSoundAt(global_position + Vector3(cellSize/2, cellSize/2, cellSize/2)) # just so we check at the center
	
	if result.is_empty():
		info.text = ""
		mesh_red.show()
		mesh_green.hide()
	else:
		info.text = "soundLevel: " + str(result.level) + "\nemitterID: " + str(result.emitter) + "\nsoundID: " + str(result.sound_id) + "\norigin: " + str(result.origin)
		mesh_red.hide()
		mesh_green.show()
