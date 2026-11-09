extends Node

signal transcribed(text: String)
signal speech_started
signal speech_ended
signal level_changed(rms:float)

@export var server_url := "http://192.168.137.1:8080/inference"
@export var threshold := 0.02        ## RMS level that counts as speech
@export var end_silence := 0.8       ## seconds of quiet that end an utterance
@export var min_speech := 0.3        ## ignore blips shorter than this
@export var preroll := 0.3           ## audio kept from before speech starts
@export var max_utterance := 20.0    ## force-send after this many seconds
@export var debug_levels := false    ## print RMS to help tune threshold
@export var micr :AudioStreamPlayer
## Set true while you play TTS so the mic doesn't hear itself.
var muted := false

const OUT_RATE := 16000


var _cap: AudioEffectCapture
var _mix_rate: float
var _buf := PackedFloat32Array()
var _speaking := false
var _speech_t := 0.0
var _silence_t := 0.0
var _queue: Array[PackedFloat32Array] = []
var _busy := false


func _ready() -> void:
	OS.request_permissions()
	_mix_rate = AudioServer.get_mix_rate()

# Muted bus + capture effect, fed by the microphone.
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "SttMic")
	AudioServer.set_bus_mute(idx, true)
	_cap = AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, _cap)

	var mic := AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "SttMic"
	add_child(mic)
	mic.play()


func _process(_delta: float) -> void:
	var n := _cap.get_frames_available()
	if n == 0:
		return
	var frames := _cap.get_buffer(n)

	if muted:
		_reset()
		level_changed.emit(0.0)
		return

	var chunk := PackedFloat32Array()
	chunk.resize(n)
	var sum := 0.0
	for i in n:
		var s := (frames[i].x + frames[i].y) * 0.5
		chunk[i] = s
		sum += s * s
	var rms := sqrt(sum / n)
	level_changed.emit(rms)
	var dur := n / _mix_rate
	_buf.append_array(chunk)

	if debug_levels:
		print("rms: %.4f" % rms)

	if rms > threshold:
		if not _speaking:
			_speaking = true
			_speech_t = 0.0
			speech_started.emit()
		_speech_t += dur
		_silence_t = 0.0
	elif _speaking:
		_silence_t += dur
		if _silence_t >= end_silence:
			_finish()
	else:
# Idle: keep only a short rolling pre-roll.
		var keep := int(preroll * _mix_rate)
		if _buf.size() > keep:
			_buf = _buf.slice(_buf.size() - keep)

	if _speaking and _buf.size() > max_utterance * _mix_rate:
		_finish()


func _finish() -> void:
	var was_long_enough := _speech_t >= min_speech
	var samples := _buf
	_reset()
	speech_ended.emit()
	if was_long_enough:
		_queue.append(_to_wav(samples))
		#_queue.append(samples)
		_send_next()


func _reset() -> void:
	_buf = PackedFloat32Array()
	_speaking = false
	_speech_t = 0.0
	_silence_t = 0.0


## Downmixed float samples -> 16 kHz mono 16-bit WAV bytes.
func _to_wav(samples: PackedFloat32Array) -> PackedByteArray:
	var ratio := _mix_rate / OUT_RATE
	var n := int(samples.size() / ratio)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var a := int(i * ratio)
		var b := mini(int((i + 1) * ratio), samples.size())
		var s := 0.0
		for j in range(a, b):
			s += samples[j]
		s /= maxi(b - a, 1)
		pcm.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	var w := StreamPeerBuffer.new()
	w.put_data("RIFF".to_ascii_buffer())
	w.put_u32(36 + pcm.size())
	w.put_data("WAVEfmt ".to_ascii_buffer())
	w.put_u32(16)
	w.put_u16(1)                 # PCM
	w.put_u16(1)                 # mono
	w.put_u32(OUT_RATE)
	w.put_u32(OUT_RATE * 2)
	w.put_u16(2)
	w.put_u16(16)
	w.put_data("data".to_ascii_buffer())
	w.put_u32(pcm.size())
	w.put_data(pcm)
	return w.data_array



func _send_next() -> void:
	if _busy or _queue.is_empty():
		return
	var wav: PackedByteArray = _queue.pop_front()
	var stre = AudioStreamWAV.new()
	stre.data = wav
	micr.stream = stre
	micr.play()
	if not micr.playing:
		push_warning("STT request failed to start:")
		return
	_busy = true





func _on_trans_completed(confidence, final_result) -> void:
	_busy = false
	print(confidence)
	if _is_real_text(final_result):
		transcribed.emit(final_result)



## Drops empty results and Whisper's non-speech tags like [BLANK_AUDIO] or (music).
func _is_real_text(text: String) -> bool:
	if text.is_empty():
		return false
	if (text.begins_with("[") and text.ends_with("]")) or (text.begins_with("(") and text.ends_with(")")):
		return false
	return true


func _on_transcribed(text: String) -> void:
	$"../Label2".text += " "+ text
