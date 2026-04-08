class_name WaveSet
extends Resource

## A finite, designer-authored campaign of WaveConfigs. main.gd reads the
## current wave by index. When the active wave index goes past the last
## entry, the run is intended to transition to the Victory screen
## (Phase 3.5 Step 20a). Until that screen ships, main.gd uses a graceful
## fallback: clamp the index to the final wave so play continues with
## the hardest tuning indefinitely.

@export var waves: Array[WaveConfig] = []


func get_wave(index: int) -> WaveConfig:
	if waves.is_empty():
		return null
	# Clamp \u2014 falling off the end re-uses the final wave instead of
	# crashing. Phase 3.5 will replace this with a victory transition.
	var clamped: int = clampi(index, 0, waves.size() - 1)
	return waves[clamped]


func is_final_wave(index: int) -> bool:
	return index >= waves.size() - 1
