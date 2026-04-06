class_name DebugOverlay
extends CanvasLayer
## F3-toggled performance overlay. Shows FPS, frame time, draw calls, etc.

const UPDATE_INTERVAL: float = 0.25

var _label: Label
var _timer: float = 0.0
var _shown: bool = false


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(4, 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	visible = false
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		_shown = not _shown
		visible = _shown
		set_process(_shown)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0
	_update_stats()


func _update_stats() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem_static: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var mem_video: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0

	# Color-code FPS
	if fps >= 58.0:
		_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps >= 30.0:
		_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		_label.add_theme_color_override("font_color", Color.RED)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS: %d (%.1f ms)" % [int(fps), frame_ms])
	lines.append("Physics: %.1f ms" % physics_ms)
	lines.append("Draw: %d | Obj: %d" % [draw_calls, objects])
	lines.append("Nodes: %d | Orphans: %d" % [nodes, orphans])
	if mem_static > 0.0:
		lines.append("Mem: %.1f MB" % mem_static)
	if mem_video > 0.0:
		lines.append("VRAM: %.1f MB" % mem_video)
	_label.text = "\n".join(lines)
