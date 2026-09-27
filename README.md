# <img width="32" height="32" alt="image" src="https://github.com/user-attachments/assets/8e78bb90-1c94-4706-ae5e-18927339bb3d" /> HKNoxel 

version 2.0 of my noise propagation system

a godot addon which adds the capability for voxel based noise propagation

<details open>
  <summary>intended for:</summary>
   
	- triggering behavior based on player sounds (like enemies reacting to footsteps, gunshots, etc.)
	- being used only in 3D environments
</details>
<details open>
  <summary>not intended for:</summary>
   
	- simulating actual sound (reflections, echos, etc.)
	- actually playing sounds
</details>

Demo scene included, just check the files once they are installed in the addons folder.
Just make sure: 
1) the addon is activated
2) KNoxelManager is set as a global named "HKNoxelManager"
3) check demo scene for a tutorial on how to set it up

## How do i use this?
Add a `NoxelMapThe` Node in your scene. The first 4 properties are fine to toy around with, while the presets for `Cell Size` and `Max Cluster` are valid and do not need adjustment.
Everything below the `DO NOT TOUCH` point should **never be touched** under any circumstance.
This plugin requires you to bake so called `Noxels` once before you start the level. For an example, check the example scene that ships with it. A thourough explanation of the steps is below:

## How does this work?
For this we assume that `Cell Size` and `Max Cluster` are set to their default value `1` and `5`.
1) First, the world is divided into tiny Chunks of the size of `1`, so the plugin can detect walls the sound **cannot** go threw
<img width="1120" height="640" alt="WallDetector" src="https://github.com/user-attachments/assets/0e0f4030-4b5b-425b-85b7-c491c45152f5" />

2) After this, an algorythm searches for Noxels which can be merged into `Clusters`. These are stricly 3 dimensional `Cubes`, having the dimensions of 1x1x1, 2x2x2, 3x3x3, 4x4x4 or 5x5x5 (depending on your `Max Cluster`). This way up to `125` Noxels are merged into `1`, saving tons of computing power.
<img width="1120" height="640" alt="Chunker" src="https://github.com/user-attachments/assets/1e916f13-4e9c-4074-b40a-9622bdd75596" />

3) As a final performence buff, neighbours of Clusters are also baked, so sound spreading from Cluster to Cluster is even more effortless
