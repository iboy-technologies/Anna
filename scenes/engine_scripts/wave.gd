extends AudioStreamPlayer

var was_speaking = false
var audio_energy =0.0
@onready var bus_idx = AudioServer.get_bus_index("Master")
@onready var spectrum = AudioServer.get_bus_effect_instance(bus_idx, 0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	audio_energy = move_toward(audio_energy, 0.0, delta*5.0)

	var mag = spectrum.get_magnitude_for_frequency_range(20, 20000, 1).length()
	var energy = clamp((60.0 + linear_to_db(mag))/60.0, 0.0, 1.0)
	audio_energy = lerp(audio_energy, energy, delta*15.0)

	#$"../ProgressBar".value = 0.01 + audio_energy * 100
	$"../ColorRect/Panel".position.y = 781 +audio_energy*100
	if playing:
		if $"../stt".playing:
			$"../stt".playing = false
	else:
		if was_speaking:
			$"../stt".playing = true
			was_speaking = false
