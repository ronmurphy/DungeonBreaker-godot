extends VoxelGeneratorScript
## Dungeon terrain generator — solid dirt floor at Y <= 0, air above.
##
## Provides a reliable floor so the player never falls into void.
## The stamper overwrites room tiles with PLANKS and builds LOG_Y walls
## that are visually distinct from the dirt base.

const AIR  = 0
const DIRT = 1
const _CHANNEL = VoxelBuffer.CHANNEL_TYPE


func _get_used_channels_mask() -> int:
	return 1 << _CHANNEL


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, _lod: int):
	var sz: Vector3i = buffer.get_size()

	# Optimisation: if the entire buffer is above Y=0, fill with air.
	if origin.y >= 1:
		buffer.fill(AIR, _CHANNEL)
		return

	# If the entire buffer is at or below Y=0, fill with dirt.
	if origin.y + sz.y <= 1:
		buffer.fill(DIRT, _CHANNEL)
		return

	# Mixed buffer — straddles the Y=0 boundary.
	for z in sz.z:
		for x in sz.x:
			for y in sz.y:
				var wy: int = origin.y + y
				if wy <= 0:
					buffer.set_voxel(DIRT, x, y, z, _CHANNEL)
				else:
					buffer.set_voxel(AIR, x, y, z, _CHANNEL)
