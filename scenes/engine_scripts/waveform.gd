class_name WaveformView
extends Control
## Scrolling mirrored-bar waveform of the mic input.
## Green while speech is detected, grey otherwise, with the VAD threshold line.

@export var stt: Node
@export var bar_width := 3.0
@export var gap := 1.0
@export var gain := 4.0                      ## visual boost for quiet mics
@export var idle_color := Color(0.55, 0.6, 0.7)
@export var speech_color := Color(0.3, 0.9, 0.5)
@export var threshold_color := Color(1.0, 0.4, 0.4, 0.6)
@export var show_threshold := true
@export var threshold := -35.0

var audio_energy =0.0
var idx = AudioServer.get_bus_index("Record")
var _levels := PackedFloat32Array()
var _flags := PackedByteArray()   # 1 = speech at that moment
var _speaking := false

func _ready() -> void:
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(400, 80)
	if stt == null:
		push_warning("WaveformView: assign the 'stt' export to an SttClient node.")
		return

func _process(delta: float) -> void:
	var rms = 0
	audio_energy = move_toward(audio_energy, 0.0, delta*5.0)

	var spec:= AudioServer.get_bus_effect_instance(idx, 4)
	var mag = spec.get_magnitude_for_frequency_range(20, 20000, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()
	var energy = clamp((60.0 + linear_to_db(mag))/60.0, 0.0, 1.0)
	audio_energy = lerp(audio_energy, energy, delta*15.0)
	rms = audio_energy*100
	_on_level(rms)
	print(rms)

func _on_level(rms: float) -> void:
	var max_bars := int(size.x / (bar_width + gap)) + 1
	_levels.append(rms)
	_flags.append(1 if _speaking else 0)
	if _levels.size() > max_bars:
		var extra := _levels.size() - max_bars
		_levels = _levels.slice(extra)
		_flags = _flags.slice(extra)
	queue_redraw()

func _draw() -> void:
	var cy := size.y * 0.5
	var step := bar_width + gap
	var count := _levels.size()

	for i in count:
		var x := size.x - (count - i) * step
		var h := maxf(clampf(_levels[i] * gain, 0.0, 1.0) * cy, 1.0)
		var col := speech_color if _flags[i] == 1 else idle_color
		draw_rect(Rect2(x, cy - h, bar_width, h * 2.0), col)

	if show_threshold and stt != null:
		var th := clampf(threshold * gain, 0.0, 1.0) * cy
		draw_line(Vector2(0, cy - th), Vector2(size.x, cy - th), threshold_color, 1.0)
		draw_line(Vector2(0, cy + th), Vector2(size.x, cy + th), threshold_color, 1.0)
