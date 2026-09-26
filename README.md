# <img width="32" height="32" alt="icon png big" src="https://github.com/user-attachments/assets/d7ca0ee4-962a-4499-ab53-8452f1cf576a" /> HKNoxel 

in VERY EARLY stages of development. this version works, but will almost certainly have problems

a godot addon which adds the capability for voxel based noise propagation

- intended to be used for making enemies react to sound you emit (footsteps, gunshots, etc.)
- not intended for actually playing or simulation physically accurate sounds, as it is not completely realistic
	- walls completely drown out the sound, dampening is not implemented
	- spreading is not based on physics (see visualization below)
<details open>
  <summary>intended for:</summary>
   
	triggering behavior based on player sounds (like enemies reacting to footsteps, gunshots, etc.)
</details>
<details open>
  <summary>not intended for:</summary>
   
	⚠️ simulating actual sound (reflections, echos, etc.)
	⚠️ actually playing sounds
</details>

Demo scene included, just check the files once they are installed in the addons folder.
just make sure: the addon is activated, HKNoxelManager is set as a global named "HKNoxelManager"

## Clustered bake

NoxelMap still checks walls at `cell_size` resolution. After that, the bake greedily groups free cells into non-overlapping cubes and records all face-adjacent cluster connections. Set `max_cluster_width` in map units to limit the cubes: the default width of 5 permits 5x5x5 cubes with `cell_size = 1`, or 10x10x10 cubes with `cell_size = 0.5`. Narrow passages stay at the fine resolution. Save the scene after baking to keep `clusterBakeData` with the wall bake; older wall-only bakes build clusters when the map loads.

Runtime sound levels and emitter IDs are stored per cluster. A wave travels one connection per physics tick, so large open cubes pass information quickly and fine cells in tight spaces pass it more slowly. Each connected face counts once toward the existing six-side falloff, even if that face touches many clusters. The cost of entering a cluster is multiplied by its side length in fine cells. A cluster has one sound level and one emitter ID throughout its volume.

Changing baked walls at runtime rebuilds the clusters and clears current sound, because the old cluster IDs no longer describe the map. Re-bake after changing `cell_size`, `max_cluster_width`, or level geometry to persist the new graph. The fine-cell lookup and baked connections increase scene or resource file size in exchange for less work during propagation.

In projects with HKConsole, the secret cheat command `debugchunks` toggles wireframe outlines of every free cluster. Small cubes are cyan and larger cubes shift toward orange. The outlines use one MultiMesh and update when the cluster bake changes. The existing `debugsound` command remains available independently: `ui_undo` emits a test sound and `ui_redo` advances one propagation tick while that mode is enabled. Both debug modes can be used together.
