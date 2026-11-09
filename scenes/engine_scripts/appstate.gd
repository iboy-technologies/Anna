extends Node

var piper_ready:bool = false
var user
const DEFAULT_PIPER_SERVER := "http://192.168.137.1:5000/synthesize"
const SETTINGS_PATH := "user://anna_settings.cfg"
var piper_server: String = DEFAULT_PIPER_SERVER
var piper_check_request: HTTPRequest
signal piper_checked
signal service_status_changed

var internet_status := "unknown"
var lan_service_status := {"Piper TTS": "unknown"}
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_load_settings()
	if FileAccess.file_exists("user://user.dat"):
		var file = FileAccess.open("user://user.dat", FileAccess.READ)
		var user_data = file.get_var()
		user = user_data["username"]
	else:
		print("no user")

func check_piper():
	if piper_check_request != null and is_instance_valid(piper_check_request):
		return
	set_lan_service_status("Piper TTS", "checking")
	piper_check_request = HTTPRequest.new()
	add_child(piper_check_request)
	piper_check_request.request_completed.connect(_check_done)
	piper_check_request.timeout = 3.0
	var error := piper_check_request.request(piper_server, [], HTTPClient.METHOD_GET, "")
	if error != OK:
		piper_ready = false
		set_lan_service_status("Piper TTS", "unavailable")
		piper_checked.emit()
		piper_check_request.queue_free()
		piper_check_request = null

func _check_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# A 405 means the local synth endpoint is reachable but does not support GET.
	piper_ready = result == HTTPRequest.RESULT_SUCCESS and (code >= 200 and code < 300 or code == 405)
	set_lan_service_status("Piper TTS", "available" if piper_ready else "unavailable")
	piper_checked.emit()
	if piper_check_request != null:
		piper_check_request.queue_free()
		piper_check_request = null

func set_internet_status(status: String) -> void:
	if status not in ["unknown", "checking", "online", "offline"]:
		push_warning("Ignoring invalid internet status: %s" % status)
		return
	if internet_status == status:
		return
	internet_status = status
	service_status_changed.emit()

func set_lan_service_status(service: String, status: String) -> void:
	if status not in ["unknown", "checking", "available", "unavailable"]:
		push_warning("Ignoring invalid LAN service status: %s" % status)
		return
	if str(lan_service_status.get(service, "")) == status:
		return
	lan_service_status[service] = status
	service_status_changed.emit()

func get_service_status_report() -> String:
	var piper_status := str(lan_service_status.get("Piper TTS", "unknown"))
	var operating_mode := "local-first"
	if internet_status == "online":
		operating_mode = "online available"
	elif internet_status == "offline" and piper_status == "available":
		operating_mode = "offline with LAN services"
	elif internet_status == "offline":
		operating_mode = "offline/local-only"
	var piper_report := "Piper TTS: " + piper_status
	if piper_status == "unavailable":
		piper_report += " (speech uses local OS TTS when available)"
	return "Internet: %s; %s; mode: %s. Typed commands and local assistant features do not require internet." % [
		internet_status,
		piper_report,
		operating_mode
	]

func _load_settings() -> void:
	var settings := ConfigFile.new()
	var error := settings.load(SETTINGS_PATH)
	if error == OK:
		var configured_url: String = str(settings.get_value("speech", "piper_url", DEFAULT_PIPER_SERVER)).strip_edges()
		if configured_url.begins_with("http://") or configured_url.begins_with("https://"):
			piper_server = configured_url
		elif not configured_url.is_empty():
			push_warning("Ignoring invalid Piper URL in %s." % SETTINGS_PATH)
	elif error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load speech settings: %s" % error_string(error))

func set_piper_server(url: String) -> Error:
	var normalized_url := url.strip_edges()
	if not normalized_url.begins_with("http://") and not normalized_url.begins_with("https://"):
		return ERR_INVALID_PARAMETER
	var settings := ConfigFile.new()
	var load_error := settings.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	settings.set_value("speech", "piper_url", normalized_url)
	var save_error := settings.save(SETTINGS_PATH)
	if save_error != OK:
		return save_error
	piper_server = normalized_url
	piper_ready = false
	set_lan_service_status("Piper TTS", "unknown")
	return OK
