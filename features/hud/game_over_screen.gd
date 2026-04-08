class_name GameOverScreen
extends CanvasLayer
## Run-end stats panel. Fades in a darkened background + slides a framed stats
## panel into view. Shows enemies sunk, shots fired, hit rate, and a scrollable
## list of per-wave completion times. Restart button reloads the current scene.
##
## Phase 3.5: same scene+script drives both the defeat and victory screens.
## `show_results(stats, victory)` picks the title/subtitle. The victory variant
## lives at scenes/victory_screen.tscn (scene inheritance — same structure).
##
## The Panel is auto-sized and centered by a full-rect CenterContainer, so we
## animate the slide by tweening the CanvasLayer's `offset` (a uniform child
## translation) instead of fighting the container's layout pass on the Panel's
## own position.

const SLIDE_DURATION: float = 0.5
const SLIDE_OFFSET_Y: float = 20.0
const BG_TARGET_ALPHA: float = 0.75

var _active_tween: Tween = null

@onready var _background: ColorRect = $Background
@onready var _panel: PanelContainer = $Centerer/Panel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _enemies_label: Label = %EnemiesValue
@onready var _mine_kills_label: Label = %MineKillsValue
@onready var _shots_label: Label = %ShotsValue
@onready var _hit_rate_label: Label = %HitRateValue
@onready var _wave_times_list: VBoxContainer = %WaveTimesList
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	assert(_background != null, "GameOverScreen: Background not found")
	assert(_panel != null, "GameOverScreen: Panel not found")
	assert(_restart_button != null, "GameOverScreen: RestartButton not found")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.modulate.a = 0.0
	_background.color.a = 0.0
	_panel.visible = false
	_background.visible = false
	_restart_button.pressed.connect(_on_restart_pressed)


func show_results(stats: RunStats, victory: bool = false) -> void:
	_populate(stats, victory)
	_panel.visible = true
	_background.visible = true
	offset = Vector2(0.0, SLIDE_OFFSET_Y)
	_panel.modulate.a = 0.0
	_background.color.a = 0.0
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.parallel().tween_property(_background, "color:a", BG_TARGET_ALPHA, SLIDE_DURATION)
	(
		_active_tween
		. parallel()
		. tween_property(self, "offset", Vector2.ZERO, SLIDE_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_active_tween.parallel().tween_property(_panel, "modulate:a", 1.0, SLIDE_DURATION)
	_active_tween.finished.connect(_on_slide_in_complete, CONNECT_ONE_SHOT)
	get_tree().paused = true


func _on_slide_in_complete() -> void:
	_restart_button.grab_focus()


func _populate(stats: RunStats, victory: bool) -> void:
	if victory:
		_title.text = "VICTORY"
		_subtitle.text = "cleared all %d waves" % maxi(stats.waves_cleared, 1)
	else:
		_title.text = "GAME OVER"
		_subtitle.text = "scuttled at wave %d" % maxi(stats.final_wave, 1)
	_enemies_label.text = str(stats.kills)
	_mine_kills_label.text = str(stats.enemies_destroyed_by_mine)
	_shots_label.text = str(stats.player_shots_fired)
	if stats.player_shots_fired <= 0:
		_hit_rate_label.text = "--"
	else:
		_hit_rate_label.text = "%d%%" % int(round(stats.hit_rate() * 100.0))
	for child: Node in _wave_times_list.get_children():
		child.queue_free()
	var row_font: Font = _subtitle.get_theme_font("font")
	for i: int in range(stats.wave_times.size()):
		var row: Label = Label.new()
		row.text = "Wave %d      %s" % [i + 1, _format_time(stats.wave_times[i])]
		row.add_theme_color_override("font_color", Color(0.9, 0.88, 0.78, 0.95))
		row.add_theme_font_override("font", row_font)
		row.add_theme_font_size_override("font_size", 12)
		_wave_times_list.add_child(row)


func _format_time(seconds: float) -> String:
	var total_ms: int = int(round(seconds * 1000.0))
	@warning_ignore("integer_division")
	var mins: int = total_ms / 60000
	@warning_ignore("integer_division")
	var secs: int = (total_ms / 1000) % 60
	@warning_ignore("integer_division")
	var tenths: int = (total_ms / 100) % 10
	return "%02d:%02d.%d" % [mins, secs, tenths]


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
