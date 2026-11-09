extends Control

signal speech_output_idle

#@onready var recogniser = $SpeechRecognizer as SpeechRecognizer
@onready var stream = $stt as AudioStreamPlayer
@onready var debug: Label = $Label3
@onready var executer = $executer

var comp_weight:float = 0.65
var s_time:String = ""
var s_date:String = ""
var speaking:bool = false
var local_tts_started := false
var local_tts_pending := false
var local_tts_pending_since := 0
var current_synth_text := ""

const BUNDLED_COMMANDS_PATH := "res://models/commands.json"
const USER_COMMANDS_PATH := "user://commands.json"
const USER_COMMANDS_DIR := "user://commands"
const FeatureLearningQueueScript = preload("res://scenes/engine_scripts/feature_learning_queue.gd")
const JournalScript = preload("res://scenes/engine_scripts/journal.gd")
const ActivityLogScript = preload("res://scenes/engine_scripts/activity_log.gd")
const DeviceRegistryScript = preload("res://scenes/engine_scripts/device_registry.gd")
const ConversationHandoffScript = preload("res://scenes/engine_scripts/conversation_handoff.gd")

var text_q: Array[String] = []
var audio_q: Array[AudioStreamWAV] = []
var synth_request_in_flight := false
var local_tts_active := false
var speech_output_pending := false
var req := HTTPRequest.new()
var feature_learning_queue
var journal
var activity_log
var device_registry
var conversation_handoff
var pending_feature_id := ""
var feature_prompt_state := ""
@onready var player := $tts






func _ready() -> void:
	var d = Time.get_date_dict_from_system()


	add_child(req)
	req.request_completed.connect(_on_synth)
	req.use_threads = true
	req.timeout = 10.0
	activity_log = ActivityLogScript.new()
	add_child(activity_log)
	feature_learning_queue = FeatureLearningQueueScript.new()
	feature_learning_queue.activity_log = activity_log
	add_child(feature_learning_queue)
	feature_learning_queue.connect("research_finished", _on_feature_research_finished)
	journal = JournalScript.new()
	add_child(journal)
	device_registry = DeviceRegistryScript.new()
	add_child(device_registry)
	conversation_handoff = ConversationHandoffScript.new()
	add_child(conversation_handoff)
	conversation_handoff.initialize(self)
	if OS.request_permission("android.permission.READ_EXTERNAL_STORAGE"):
		pass
	else:
		OS.request_permission("android.permission.READ_EXTERNAL_STORAGE")
		#piper_speak("Hello there Moo rae, how are you?, are your tootwas okay?")
func prep():
	load_s()
	journal.maybe_prompt_today()
	call_deferred("greet")

func load_s():
	s_time = Time.get_time_string_from_system()
	print(s_time)
	s_date = Time.get_date_string_from_system()
	print(s_date)

func greet():
	var greeting = ""
	var time_int = int(s_time.split(":")[0])
	print(time_int)
	if time_int <12:
		greeting = "Good morning, "+ Appstate.user
	elif time_int >11 && time_int < 17:
		greeting = "Good afternoon, "+ Appstate.user
	else:
		greeting = "Good evening, "+ Appstate.user
	Appstate.check_piper()
	piper_speak(greeting)

func _process(_delta: float) -> void:
	if not local_tts_started and not local_tts_pending:
		return
	if DisplayServer.tts_is_speaking():
		local_tts_started = true
		local_tts_pending = false
	elif local_tts_started:
		local_tts_started = false
		local_tts_active = false
		if Appstate.piper_ready:
			_pump()
		else:
			_pump2()
		_emit_speech_idle_if_needed()
	elif Time.get_ticks_msec() - local_tts_pending_since > 5000:
		push_warning("Local text-to-speech did not start; skipping this utterance.")
		local_tts_pending = false
		local_tts_active = false
		if Appstate.piper_ready:
			_pump()
		else:
			_pump2()
		_emit_speech_idle_if_needed()




#///////////////////SPEECH////////////////////////////
#////////////////////////////////////////////////////
func _on_start_pressed() -> void:
	if not has_node("SpeechRecognizer"):
		debug.text = "Offline voice input is not installed. Type your request instead."
		return
	if ! stream.is_playing():
		if OS.get_name() == "Android":
			if OS.request_permission("android.permission.RECORD_AUDIO"):
				stream.play()
				$Button.set_modulate(Color(1.0, 0.471, 0.286))
			else:
				if OS.request_permission("android.permission.RECORD_AUDIO"):
					stream.play()
					$Button.set_modulate(Color(1.0, 0.471, 0.286))
		else:
			stream.play()
			$Button.set_modulate(Color(1.0, 0.471, 0.286))
	else:
		stream.stop()
		$Button.set_modulate(Color(0.78, 0.259, 0.0))

func _on_speech_recognizer_result(_confidence: float, text: String) -> void:
	$Label2.text = text
	process_speech(text)

func _on_speech_recognizer_partial_result(text: String) -> void:
	print(text)
	#$Label2.text=""
	$Label2.text += text

func _on_input_t_text_submitted(new_text: String) -> void:
	process_speech(new_text)
	$input_t.clear()
	$out.text = ""
	$out/TextEdit.text += "\n\n"
	$out/TextEdit.text += Appstate.user + ": " + new_text
	$out/TextEdit.text += "\n"
#//////////////////////////////////////////////////





#////////////////////COMMAND PROCESS///////////////////
#/////////////////////////////////////////////////////
func process_speech(text:String):
	if _is_conversation_handoff_command(text):
		conversation_handoff.open_handoff()
		return
	if _is_device_registry_command(text):
		device_registry.open_registry()
		return
	if _is_activity_log_command(text):
		activity_log.show_log()
		return
	if _is_journal_command(text):
		journal.open_journal()
		return
	if _is_service_status_command(text):
		var status_message := Appstate.get_service_status_report()
		_append_assistant_message(status_message)
		piper_speak(status_message)
		return
	if _handle_feature_prompt_reply(text):
		return
	if text.strip_edges().to_lower() in ["learn next", "learn next feature", "research next queued feature"]:
		pending_feature_id = feature_learning_queue.promote_next_queued_request()
		if pending_feature_id.is_empty():
			var empty_message := "There are no feature requests waiting in the local learning queue."
			_append_assistant_message(empty_message)
			piper_speak(empty_message)
		else:
			feature_prompt_state = "choice"
			_show_feature_choice()
		return
	if _check_commands(text) == true:
		return
	if _is_unsupported_feature_request(text):
		var existing_id: String = feature_learning_queue.find_request_id(text)
		pending_feature_id = feature_learning_queue.promote_request(text)
		if not existing_id.is_empty():
			feature_prompt_state = "checking"
			var retry_message := "I moved that existing request to the top of the learning queue and am checking connectivity again."
			_append_assistant_message(retry_message)
			piper_speak(retry_message)
			if not feature_learning_queue.start_research(pending_feature_id):
				feature_prompt_state = "choice"
				_show_feature_choice()
			return
		feature_prompt_state = "choice"
		_show_feature_choice()
		return

	#_check_house(text)
	#check_car(text)
	if check_dialogue(text) == true:
		pass

func _is_device_registry_command(text: String) -> bool:
	return text.strip_edges().to_lower() in [
		"device registry", "devices", "manage devices", "feature registry",
		"capability route", "request capability", "household status"
	]

func _is_conversation_handoff_command(text: String) -> bool:
	return text.strip_edges().to_lower() in [
		"handoff", "conversation handoff", "transfer conversation", "share conversation"
	]

func _is_activity_log_command(text: String) -> bool:
	return text.strip_edges().to_lower() in [
		"activity log", "show activity log", "view activity log", "privacy log"
	]

func _is_journal_command(text: String) -> bool:
	return text.strip_edges().to_lower() in [
		"journal", "open journal", "daily journal", "write journal", "journal entry"
	]

func _is_service_status_command(text: String) -> bool:
	return text.strip_edges().to_lower() in [
		"status", "connectivity status", "network status", "service status", "system status"
	]

func _is_unsupported_feature_request(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return false
	var action_terms := [
		"add ", "support ", "connect ", "integrate ", "control ", "automate ",
		"enable ", "teach yourself", "learn how to", "remember to", "pair ",
		"configure ", "turn on ", "turn off "
	]
	for term in action_terms:
		if normalized.contains(term):
			return true
	return false

func _show_feature_choice() -> void:
	var message := "That capability is not available in ANNA yet. Reply Learn now, Learn later, or Not now. Learn now checks internet and gathers sourced research; if configured, the request and excerpts are sent to your selected online model to draft a proposal. Nothing is installed, run, or applied to device settings."
	_append_assistant_message(message)
	piper_speak(message)

func _handle_feature_prompt_reply(text: String) -> bool:
	if feature_prompt_state.is_empty():
		return false
	var answer := text.strip_edges().to_lower()
	if feature_prompt_state in ["choice", "offline", "checking"] and _is_unsupported_feature_request(text):
		var previous_id := pending_feature_id
		var requested_id: String = feature_learning_queue.promote_request(text)
		if requested_id == previous_id:
			feature_prompt_state = "checking"
			var retry_message := "I recognized the same feature request again, moved it to the top of the queue, and am checking connectivity before researching it."
			_append_assistant_message(retry_message)
			piper_speak(retry_message)
			feature_learning_queue.start_research(requested_id)
		else:
			feature_learning_queue.defer_request(requested_id)
			var queued_message := "I saved that different feature request to the bottom of the queue. Please finish the current Learn now, Learn later, or Not now choice first."
			_append_assistant_message(queued_message)
			piper_speak(queued_message)
		return true
	if feature_prompt_state == "choice":
		if answer in ["learn now", "learn", "yes", "research now"]:
			feature_prompt_state = "checking"
			var message := "I will check connectivity and research this feature using sources."
			_append_assistant_message(message)
			piper_speak(message)
			if not feature_learning_queue.start_research(pending_feature_id):
				feature_prompt_state = "choice"
				_show_feature_choice()
			return true
		if answer in ["learn later", "later", "save for later"]:
			feature_learning_queue.defer_request(pending_feature_id)
			feature_prompt_state = ""
			var message := "Saved to the bottom of the local learning queue. No feature or device action was performed."
			_append_assistant_message(message)
			piper_speak(message)
			pending_feature_id = ""
			return true
		if answer in ["not now", "no", "cancel"]:
			feature_learning_queue.mark_not_now(pending_feature_id)
			feature_prompt_state = ""
			var message := "Okay. I left the request unlearned and made no changes."
			_append_assistant_message(message)
			piper_speak(message)
			pending_feature_id = ""
			return true
		_show_feature_choice()
		return true
	if feature_prompt_state == "offline":
		if answer in ["retry", "try again", "learn now"]:
			feature_prompt_state = "checking"
			var message := "Retrying the internet check."
			_append_assistant_message(message)
			piper_speak(message)
			if not feature_learning_queue.start_research(pending_feature_id):
				feature_prompt_state = "offline"
			return true
		if answer in ["learn later", "later", "save for later"]:
			feature_learning_queue.defer_request(pending_feature_id)
			feature_prompt_state = ""
			var message := "Saved to the bottom of the local learning queue."
			_append_assistant_message(message)
			piper_speak(message)
			pending_feature_id = ""
			return true
		_append_assistant_message("Reply Retry or Learn later.")
		return true
	return true

func _append_assistant_message(message: String) -> void:
	var transcript: TextEdit = $out/TextEdit
	transcript.text += "\nANNA: " + message + "\n"
	transcript.scroll_vertical = 20000

func _on_feature_research_finished(request_id: String, outcome: String, report: String) -> void:
	if request_id != pending_feature_id:
		return
	if outcome == "offline":
		feature_prompt_state = "offline"
		_append_assistant_message(report + " Reply Retry or Learn later.")
		piper_speak(report + " Say Retry or Learn later.")
		return
	feature_prompt_state = ""
	_append_assistant_message(report)
	piper_speak(report)
	pending_feature_id = ""

func _check_commands(what:String):
	var data := _load_commands()
	var commands = data.keys()
	#iterate through the comands
	for cmd in commands:
		var triggers = data[cmd]
		#iterate through the trigers array
		for phrase in triggers:
			if phrase.similarity(what) > comp_weight:
				execute(cmd)
				return true
	return false

func _load_commands() -> Dictionary:
	var commands := _read_commands(BUNDLED_COMMANDS_PATH)
	var learned := _load_learned_commands()
	for cmd in learned:
		if commands.has(cmd):
			commands[cmd].append_array(learned[cmd])
		else:
			commands[cmd] = learned[cmd]
	return commands

func _load_learned_commands() -> Dictionary:
	return _read_commands(USER_COMMANDS_PATH)

func _read_commands(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not read command database %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var contents := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(contents)
	if not parsed is Dictionary:
		push_error("Command database %s does not contain a JSON object." % path)
		return {}

	var commands: Dictionary = {}
	for command in parsed:
		if not _is_valid_command_name(str(command)):
			push_warning("Ignoring invalid command name in %s: %s" % [path, str(command)])
			continue
		if not parsed[command] is Array:
			push_warning("Ignoring command with invalid triggers in %s: %s" % [path, str(command)])
			continue
		var triggers: Array[String] = []
		for trigger in parsed[command]:
			if trigger is String and not trigger.strip_edges().is_empty():
				triggers.append(trigger.strip_edges())
		commands[str(command)] = triggers
	return commands

func _is_valid_command_name(command: String) -> bool:
	if command.length() > 48:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_.-]*$")
	return command != "." and command != ".." and pattern.search(command) != null

func execute(command):
	if not _is_valid_command_name(command):
		push_error("Refusing to execute an invalid command name: %s" % command)
		return
	var script_path := USER_COMMANDS_DIR + "/" + command + ".dan"
	if not FileAccess.file_exists(script_path):
		script_path = "res://scripts/" + command + ".dan"
	if not FileAccess.file_exists(script_path):
		push_error("No script found for command: %s" % command)
		return
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		push_error("Could not read command script %s: %s" % [script_path, error_string(FileAccess.get_open_error())])
		return
	var source := file.get_as_text()
	file.close()
	var scr = GDScript.new()
	scr.source_code = "extends Node\n" + source
	if scr.reload() != OK:
		push_error("Could not compile command script: %s" % script_path)
		return
	executer.set_script(scr)
	if not executer.has_method("run"):
		push_error("Command script has no run() method: %s" % script_path)
		executer.set_script(null)
		return
	var output = executer.call("run")
	print(output)
	activity_log.record_event("command_execution", {
		"command": str(command),
		"outcome": "completed"
	})


func check_dialogue(text):
	#print("yoyooyoyoyo")
	$layers/l4.ask(text)
#//////////////////////////////////////////////////////////





#////////////////////////////////////////////////////
#////////////////////PIPER///////////////////////////
func piper_speak(text:String):
	var cleaned := _clean(text)
	if cleaned.is_empty():
		return false
	speech_output_pending = true
	if Appstate.piper_ready:
		text_q.append(cleaned)
		_pump()
		return true
	else:
		activity_log.record_event("connectivity_fallback", {
			"service": "Piper TTS",
			"outcome": "piper_unavailable"
		})
		text_q.append(cleaned)
		_pump2()
	return true

func _clean(t: String) -> String:
	return t.replace("*", "").replace("#", "").replace("`", "").strip_edges()

func _pump():
	if local_tts_active:
		return
	if not synth_request_in_flight and Appstate.piper_ready and text_q.size() > 0:
		synth_request_in_flight = true
		current_synth_text = text_q.pop_front()
		var error := req.request(Appstate.piper_server, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"text": current_synth_text}))
		if error != OK:
			_fallback_to_local_tts(current_synth_text, "Could not start Piper request: %s" % error_string(error))
	if not player.playing and audio_q.size() > 0:
		player.stream = audio_q.pop_front()
		player.play()
		player.was_speaking = true
		#speaking = true
	_emit_speech_idle_if_needed()

func _fallback_to_local_tts(text: String, reason: String) -> void:
	push_warning("%s Switching to local system speech." % reason)
	activity_log.record_event("connectivity_fallback", {
		"service": "Piper TTS",
		"outcome": "local_os_tts"
	})
	Appstate.piper_ready = false
	Appstate.set_lan_service_status("Piper TTS", "unavailable")
	synth_request_in_flight = false
	current_synth_text = ""
	if not text.is_empty():
		text_q.push_front(text)
	_pump2()

func _pump2():
	if local_tts_active or synth_request_in_flight or player.playing or not audio_q.is_empty() or text_q.is_empty():
		return
	var voices := DisplayServer.tts_get_voices_for_language("en_GB")
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices_for_language("en_US")
	if voices.is_empty():
		push_warning("No local text-to-speech voice is installed; speech output is unavailable.")
		text_q.clear()
		_emit_speech_idle_if_needed()
		return
	if DisplayServer.tts_is_speaking():
		local_tts_active = true
		local_tts_started = true
		local_tts_pending = false
		return
	local_tts_active = true
	local_tts_started = false
	local_tts_pending = true
	local_tts_pending_since = Time.get_ticks_msec()
	DisplayServer.tts_speak(text_q.pop_front(), voices[0])
func _on_synth(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var spoken_text := current_synth_text
	current_synth_text = ""
	synth_request_in_flight = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 44:
		var w := wav_to_bytes(body)
		if w == null:
			_fallback_to_local_tts(spoken_text, "Piper returned an invalid WAV response.")
			return
		Appstate.set_lan_service_status("Piper TTS", "available")
		audio_q.append(w)
		_pump()
		return
	var reason := "Piper request timed out or failed." if result != HTTPRequest.RESULT_SUCCESS else "Piper returned HTTP %d or an empty audio response." % code
	_fallback_to_local_tts(spoken_text, reason)




func _on_tts_finished() -> void:
	speaking = false
	if not audio_q.is_empty():
		_pump()
	elif not synth_request_in_flight and not Appstate.piper_ready:
		_pump2()
	else:
		_pump()
	_emit_speech_idle_if_needed()

func _is_speech_output_idle() -> bool:
	return text_q.is_empty() and audio_q.is_empty() and not synth_request_in_flight and not local_tts_active and not player.playing

func _emit_speech_idle_if_needed() -> void:
	if speech_output_pending and _is_speech_output_idle():
		speech_output_pending = false
		speech_output_idle.emit()



func wav_to_bytes(bytes: PackedByteArray):
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var channels = bytes.decode_u16(22)
	var sample_rate = bytes.decode_u32(24)
	var format = bytes.decode_u16(20)
	var bits_per_sample = bytes.decode_u16(34)
	if format != 1 or channels < 1 or channels > 2 or sample_rate == 0 or not (bits_per_sample == 8 or bits_per_sample == 16):
		return null
	var stre = AudioStreamWAV.new()
	stre.mix_rate = sample_rate
	stre.stereo = channels ==2
	stre.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
	stre.data = bytes.slice(44)
	return stre

#/////////////////////////////////////////////////////////











#/////////////////CODE LEARNING/////////////
#//////////////////////////////////////////
func _on_test_run_pressed() -> void:
	$executer/CodeEdit/progress.show()
	$executer/CodeEdit/progress/Button2.hide()
	$executer/CodeEdit/progress/Button3.hide()
	$executer/CodeEdit/progress/CheckBox.set_pressed(false)
	$executer/CodeEdit/progress/CheckBox2.set_pressed(false)
	$executer/CodeEdit/progress/CheckBox3.set_pressed(false)
	#executes to test for syntax and runtime errors in script
	var user_code = $executer/CodeEdit.text
	var scr = GDScript.new()
	var s_code = "extends Node\n"+user_code
	scr.source_code = s_code
	if scr.reload() != OK:
		print("syntax error")
	else:
		$executer/CodeEdit/progress/CheckBox.set_pressed(true)
		print("syntax is ok proceeding to run code")
		var test_exec = Node.new()
		add_child(test_exec)
		test_exec.set_script(scr)
		if test_exec.run():
			$executer/CodeEdit/progress/CheckBox2.set_pressed(true)
			print("execution complete")
			test_exec.queue_free()
			$executer/CodeEdit/progress/CheckBox3.set_pressed(true)
			_on_test_run_complete()

func _on_test_run_complete() -> void:
	$executer/CodeEdit/progress/Button2.show()
	$executer/CodeEdit/progress/Button3.show()

func _on_save_code_pressed() -> void:
	$executer/CodeEdit/progress/Button2.hide()
	$executer/CodeEdit/progress/Button3.hide()
	$executer/CodeEdit/progress.hide()
	$executer/CodeEdit/confirm.show()

func _on_edit_code_pressed() -> void:
	$executer/CodeEdit/progress/Button2.hide()
	$executer/CodeEdit/progress/Button3.hide()
	$executer/CodeEdit/progress.hide()


func _on_finish_extension_pressed() -> void:
	$executer/CodeEdit/confirm/error.hide()
	var cmd: String = $executer/CodeEdit/confirm/cmd_name.text.strip_edges()
	var triggers: String = $executer/CodeEdit/confirm/triggers.text
	if not _is_valid_command_name(cmd) or triggers.strip_edges().is_empty():
		$executer/CodeEdit/confirm/error.text = "Enter a valid command name and at least one trigger."
		$executer/CodeEdit/confirm/error.show()
		return
	if _load_commands().has(cmd):
		$executer/CodeEdit/confirm/error.text = "command name exists, try another."
		$executer/CodeEdit/confirm/error.show()
		return

	var learned: Dictionary = {}
	var trigger_arr: Array[String] = []
	for trigger in triggers.split(","):
		var cleaned := trigger.strip_edges()
		if not cleaned.is_empty() and not trigger_arr.has(cleaned):
			trigger_arr.append(cleaned)
	if trigger_arr.is_empty():
		$executer/CodeEdit/confirm/error.text = "Enter at least one non-empty trigger."
		$executer/CodeEdit/confirm/error.show()
		return

	var dir_path := ProjectSettings.globalize_path(USER_COMMANDS_DIR)
	var make_dir_error := DirAccess.make_dir_recursive_absolute(dir_path)
	if make_dir_error != OK and not DirAccess.dir_exists_absolute(dir_path):
		$executer/CodeEdit/confirm/error.text = "Could not create the user command directory: " + error_string(make_dir_error)
		$executer/CodeEdit/confirm/error.show()
		return
	var script_path := USER_COMMANDS_DIR + "/" + cmd + ".dan"
	if FileAccess.file_exists(script_path):
		$executer/CodeEdit/confirm/error.text = "A local command script with this name already exists."
		$executer/CodeEdit/confirm/error.show()
		return
	var script_file := FileAccess.open(script_path, FileAccess.WRITE)
	if script_file == null:
		$executer/CodeEdit/confirm/error.text = "Could not save command script: " + error_string(FileAccess.get_open_error())
		$executer/CodeEdit/confirm/error.show()
		return
	script_file.store_string($executer/CodeEdit.text)
	script_file.flush()
	var script_error := script_file.get_error()
	script_file.close()
	if script_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
		$executer/CodeEdit/confirm/error.text = "Failed while writing the command script."
		$executer/CodeEdit/confirm/error.show()
		return

	var had_previous_database := FileAccess.file_exists(USER_COMMANDS_PATH)
	var previous_database := ""
	if had_previous_database:
		var previous_file := FileAccess.open(USER_COMMANDS_PATH, FileAccess.READ)
		if previous_file == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
			$executer/CodeEdit/confirm/error.text = "Could not read the existing command database: " + error_string(FileAccess.get_open_error())
			$executer/CodeEdit/confirm/error.show()
			return
		previous_database = previous_file.get_as_text()
		previous_file.close()
		if not JSON.parse_string(previous_database) is Dictionary:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
			$executer/CodeEdit/confirm/error.text = "The existing command database is invalid; it was not overwritten."
			$executer/CodeEdit/confirm/error.show()
			return

	learned = _load_learned_commands()
	learned[cmd] = trigger_arr
	var command_file := FileAccess.open(USER_COMMANDS_PATH, FileAccess.WRITE)
	if command_file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
		$executer/CodeEdit/confirm/error.text = "Could not save command database: " + error_string(FileAccess.get_open_error())
		$executer/CodeEdit/confirm/error.show()
		return
	command_file.store_string(JSON.stringify(learned))
	command_file.flush()
	var database_error := command_file.get_error()
	command_file.close()
	if database_error != OK:
		_rollback_new_command(script_path, previous_database, had_previous_database)
		$executer/CodeEdit/confirm/error.text = "Failed while writing the command database."
		$executer/CodeEdit/confirm/error.show()
		return
	$executer/CodeEdit/confirm.hide()
	$executer/CodeEdit.hide()

func _rollback_new_command(script_path: String, previous_database: String, had_previous_database: bool) -> void:
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))
	if remove_error != OK:
		push_error("Could not remove incomplete command script: " + error_string(remove_error))
	if had_previous_database:
		var restore_file := FileAccess.open(USER_COMMANDS_PATH, FileAccess.WRITE)
		if restore_file == null:
			push_error("Could not restore the previous command database: " + error_string(FileAccess.get_open_error()))
			return
		restore_file.store_string(previous_database)
		restore_file.flush()
		var restore_error := restore_file.get_error()
		restore_file.close()
		if restore_error != OK:
			push_error("Could not restore the previous command database after a write failure.")
	else:
		var remove_db_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_COMMANDS_PATH))
		if remove_db_error != OK and remove_db_error != ERR_DOES_NOT_EXIST:
			push_error("Could not remove incomplete command database: " + error_string(remove_db_error))

#/////////////////////////////////////////////////////








#////////////////BACK PRESSED//////////////////
#/////////////////////////////////////////////
func _input(event: InputEvent) -> void:
	if event.is_pressed() && event is InputEventKey:
		if event.keycode == KEY_BACK or event.keycode == KEY_ESCAPE:
			if $executer/CodeEdit/confirm.is_visible():
				$executer/CodeEdit/confirm.hide()
			elif $executer/CodeEdit/progress.is_visible():
				$executer/CodeEdit/progress.hide()
			elif $executer/CodeEdit.is_visible():
				$executer/CodeEdit.hide()
			else:
				piper_speak("Have a good day!")
				if not _is_speech_output_idle():
					await speech_output_idle
				get_tree().quit()


#


func _on_wakeup_result(confidence: float, text: String) -> void:
	if text == "Anna":
		print("waking")
		$stt.play()
	print(text)
