extends Node

signal pairing_requested(peer_id: int, request: Dictionary)
signal pairing_commit_requested(peer_id: int, device: Dictionary)
signal pairing_aborted(device: Dictionary)
signal pairing_finished(accepted: bool, message: String)
signal hub_status_changed(message: String)

const HUB_KEY_PATH := "user://anna_hub_private.key"
const HUB_CERT_PATH := "user://anna_hub.crt"
const CLIENT_ID_PATH := "user://anna_device_id.txt"
const PAIRED_HUB_PATH := "user://anna_paired_hub.json"
const PAIR_CODE_TTL_MSEC := 120000
const PAIR_CONFIRMATION_TTL_MSEC := 30000
const CLIENT_CONNECT_TIMEOUT_MSEC := 45000
const MAX_PAIR_PACKET_BYTES := 16384
const PAIR_PROTOCOL := 1

var _hub_peer: WebSocketMultiplayerPeer
var _client_peer: WebSocketMultiplayerPeer
var _crypto := Crypto.new()
var _pair_code := ""
var _pair_code_expiry := 0
var _client_request: Dictionary = {}
var _client_request_sent := false
var _pending_peer_id := 0
var _pending_pairing_deadline := 0
var _pending_device: Dictionary = {}
var _pending_commit_received := false
var _hub_approved_pending := false
var _connection_deadline := 0
var _client_address := ""
var _client_port := 0
var _client_certificate_pem := ""
var _client_device_id := ""
var _hub_status := "Hub transport stopped."


func _process(_delta: float) -> void:
	if _hub_peer != null:
		_hub_peer.poll()
		_read_hub_packets()
	if _client_peer != null:
		_client_peer.poll()
		_process_client()
	if _pending_peer_id != 0 and Time.get_ticks_msec() > _pending_pairing_deadline:
		if not _pending_device.is_empty():
			pairing_aborted.emit(_pending_device.duplicate(true))
		if _hub_peer != null:
			_hub_peer.disconnect_peer(_pending_peer_id, true)
		_pending_peer_id = 0
		_pending_pairing_deadline = 0
		_pending_device.clear()
		_pending_commit_received = false
		_hub_approved_pending = false
		hub_status_changed.emit("Client confirmation timed out.")
	if not _pair_code.is_empty() and Time.get_ticks_msec() > _pair_code_expiry:
		_pair_code = ""
		_pair_code_expiry = 0
		hub_status_changed.emit("Pairing invitation expired; generate a new code.")


func start_hub(bind_address: String, port: int) -> Error:
	if not _is_desktop() or not _is_local_bind_address(bind_address):
		return ERR_INVALID_PARAMETER
	if port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	if _hub_peer != null:
		stop_hub()
	var tls_options := _load_or_create_server_tls()
	if tls_options == null:
		return ERR_CANT_OPEN
	var server := WebSocketMultiplayerPeer.new()
	server.inbound_buffer_size = MAX_PAIR_PACKET_BYTES
	server.outbound_buffer_size = MAX_PAIR_PACKET_BYTES
	server.max_queued_packets = 16
	var error := server.create_server(port, bind_address, tls_options)
	if error != OK:
		return error
	_hub_peer = server
	_hub_peer.peer_connected.connect(_on_hub_peer_connected)
	_hub_peer.peer_disconnected.connect(_on_hub_peer_disconnected)
	_hub_status = "TLS WebSocket hub listening on %s:%d." % [bind_address, port]
	hub_status_changed.emit(_hub_status)
	return OK


func stop_hub() -> void:
	_pair_code = ""
	_pair_code_expiry = 0
	if _pending_peer_id != 0 and not _pending_device.is_empty():
		pairing_aborted.emit(_pending_device.duplicate(true))
	_pending_peer_id = 0
	_pending_pairing_deadline = 0
	_pending_device.clear()
	_pending_commit_received = false
	_hub_approved_pending = false
	if _hub_peer != null:
		_hub_peer.close()
		_hub_peer = null
	_hub_status = "Hub transport stopped."
	hub_status_changed.emit(_hub_status)


func create_pairing_invitation() -> String:
	if _hub_peer == null or _pending_peer_id != 0:
		return ""
	var random_bytes := _crypto.generate_random_bytes(32)
	if random_bytes.size() != 32:
		push_error("Could not generate cryptographically secure pairing invitation bytes.")
		return ""
	_pair_code = random_bytes.hex_encode()
	_pair_code_expiry = Time.get_ticks_msec() + PAIR_CODE_TTL_MSEC
	return _pair_code


func connect_client(address: String, port: int, code: String, certificate_pem: String, device_name: String, device_type: String, capabilities: Array[String], user_consented: bool) -> Error:
	if OS.get_name() != "Android":
		return ERR_UNAUTHORIZED
	if _client_peer != null:
		return ERR_ALREADY_IN_USE
	if not user_consented:
		return ERR_UNAUTHORIZED
	if not _is_valid_ipv4_address(address) or port < 1024 or port > 65535:
		return ERR_INVALID_PARAMETER
	if not _is_valid_pair_code(code):
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(PAIRED_HUB_PATH):
		return ERR_ALREADY_IN_USE
	var certificate := X509Certificate.new()
	if certificate.load_from_string(certificate_pem) != OK:
		return ERR_INVALID_DATA
	if device_name.strip_edges().is_empty() or device_type != "Android":
		return ERR_INVALID_PARAMETER
	_client_device_id = _load_or_create_client_id()
	if _client_device_id.is_empty():
		return ERR_CANT_CREATE
	_client_address = address
	_client_port = port
	_client_certificate_pem = certificate.save_to_string()
	_client_request = {
		"protocol": PAIR_PROTOCOL,
		"type": "pair_request",
		"pair_code": code,
		"device": {
			"id": _client_device_id,
			"name": device_name.strip_edges().substr(0, 64),
			"type": device_type,
			"capabilities": _sanitize_capabilities(capabilities)
		},
		"client_consent": true
	}
	var client := WebSocketMultiplayerPeer.new()
	client.inbound_buffer_size = MAX_PAIR_PACKET_BYTES
	client.outbound_buffer_size = MAX_PAIR_PACKET_BYTES
	client.max_queued_packets = 16
	var error := client.create_client("wss://%s:%d" % [address, port], TLSOptions.client(certificate, "ANNA Hub"))
	if error != OK:
		_client_request.clear()
		return error
	_client_peer = client
	_client_request_sent = false
	_connection_deadline = Time.get_ticks_msec() + CLIENT_CONNECT_TIMEOUT_MSEC
	return OK


func approve_pairing(peer_id: int, accepted: bool, message: String = "") -> void:
	if _hub_peer == null or peer_id != _pending_peer_id:
		return
	_hub_approved_pending = accepted
	_send_hub_message(peer_id, {
		"protocol": PAIR_PROTOCOL,
		"type": "hub_approved",
		"accepted": accepted,
		"message": message.substr(0, 160)
	})
	if accepted:
		_pair_code = ""
		_pair_code_expiry = 0
	else:
		_pending_peer_id = 0
		_pending_pairing_deadline = 0
		_pending_device.clear()
		_hub_peer.disconnect_peer(peer_id, true)


func get_hub_status() -> String:
	return _hub_status


func get_certificate_text() -> String:
	var certificate := X509Certificate.new()
	if certificate.load(HUB_CERT_PATH) != OK:
		return ""
	return certificate.save_to_string()


func forget_paired_hub() -> Error:
	if not FileAccess.file_exists(PAIRED_HUB_PATH):
		return ERR_DOES_NOT_EXIST
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(PAIRED_HUB_PATH))


func _load_or_create_server_tls() -> TLSOptions:
	var key := CryptoKey.new()
	var certificate := X509Certificate.new()
	var key_exists := FileAccess.file_exists(HUB_KEY_PATH)
	var cert_exists := FileAccess.file_exists(HUB_CERT_PATH)
	if key_exists != cert_exists:
		push_error("Hub TLS key and certificate are mismatched; refusing to start.")
		return null
	if key_exists:
		if key.load(HUB_KEY_PATH) != OK or certificate.load(HUB_CERT_PATH) != OK:
			push_error("Could not load the hub TLS key and certificate.")
			return null
	else:
		key = _crypto.generate_rsa(4096)
		if key == null:
			push_error("Could not generate the hub TLS key.")
			return null
		certificate = _crypto.generate_self_signed_certificate(key, "CN=ANNA Hub,O=ANNA,C=US")
		if certificate == null:
			push_error("Could not generate the hub TLS certificate.")
			return null
		if key.save(HUB_KEY_PATH) != OK or certificate.save(HUB_CERT_PATH) != OK:
			push_error("Could not persist hub TLS credentials; the network listener will not start.")
			return null
	return TLSOptions.server(key, certificate)


func _on_hub_peer_connected(peer_id: int) -> void:
	if not _pair_code.is_empty() and Time.get_ticks_msec() <= _pair_code_expiry and _pending_peer_id == 0:
		_pending_peer_id = peer_id
		_pending_pairing_deadline = Time.get_ticks_msec() + PAIR_CONFIRMATION_TTL_MSEC
		return
	_hub_peer.disconnect_peer(peer_id, true)


func _on_hub_peer_disconnected(peer_id: int) -> void:
	if _pending_peer_id == peer_id:
		if not _pending_device.is_empty():
			pairing_aborted.emit(_pending_device.duplicate(true))
		_pending_peer_id = 0
		_pending_pairing_deadline = 0
		_pending_device.clear()
		_pending_commit_received = false
		_hub_approved_pending = false


func _read_hub_packets() -> void:
	while _hub_peer != null and _hub_peer.get_available_packet_count() > 0:
		var peer_id := _hub_peer.get_packet_peer()
		var packet := _hub_peer.get_packet()
		if packet.size() > MAX_PAIR_PACKET_BYTES:
			_pair_code = ""
			_pair_code_expiry = 0
			_hub_peer.disconnect_peer(peer_id, true)
			continue
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if peer_id != _pending_peer_id:
			_hub_peer.disconnect_peer(peer_id, true)
			continue
		if parsed is Dictionary and str(parsed.get("type", "")) == "pair_commit":
			if int(parsed.get("protocol", -1)) != PAIR_PROTOCOL or not bool(parsed.get("client_storage_ready", false)) or _pending_device.is_empty() or not _hub_approved_pending or _pending_commit_received:
				_pending_pairing_deadline = 0
				_hub_peer.disconnect_peer(peer_id, true)
				continue
			_pending_commit_received = true
			pairing_commit_requested.emit(peer_id, _pending_device.duplicate(true))
			continue
		if not _valid_pair_request(parsed):
			_pair_code = ""
			_pair_code_expiry = 0
			_hub_peer.disconnect_peer(peer_id, true)
			continue
		_pair_code = ""
		_pair_code_expiry = 0
		_pending_device = parsed["device"].duplicate(true)
		_pending_pairing_deadline = Time.get_ticks_msec() + PAIR_CONFIRMATION_TTL_MSEC
		pairing_requested.emit(peer_id, parsed["device"])


func _valid_pair_request(value) -> bool:
	if not value is Dictionary:
		return false
	if int(value.get("protocol", -1)) != PAIR_PROTOCOL or str(value.get("type", "")) != "pair_request":
		return false
	if not bool(value.get("client_consent", false)) or not _is_valid_pair_code(str(value.get("pair_code", ""))):
		return false
	if not _crypto.constant_time_compare(_pair_code.to_utf8_buffer(), str(value.get("pair_code", "")).to_utf8_buffer()):
		return false
	var device = value.get("device", {})
	if not device is Dictionary:
		return false
	if device.get("capabilities", []) is Array and device["capabilities"].size() > 32:
		return false
	var device_name := str(device.get("name", "")).strip_edges()
	if not _is_valid_device_id(str(device.get("id", ""))) or device_name.is_empty() or device_name.length() > 64:
		return false
	if str(device.get("type", "")) != "Android":
		return false
	if not device.get("capabilities", []) is Array:
		return false
	for capability in device["capabilities"]:
		if not capability is String or capability.strip_edges().is_empty() or capability.length() > 64:
			return false
	return true


func _process_client() -> void:
	if _client_peer == null:
		return
	if _client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not _client_request_sent:
		_send_client_request()
	while _client_peer != null and _client_peer.get_available_packet_count() > 0:
		var packet := _client_peer.get_packet()
		if packet.size() > MAX_PAIR_PACKET_BYTES:
			_finish_client(false, "The hub sent an oversized pairing response.")
			return
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if not parsed is Dictionary or int(parsed.get("protocol", -1)) != PAIR_PROTOCOL:
			_finish_client(false, "The hub sent an invalid pairing response.")
			return
		match str(parsed.get("type", "")):
			"hub_approved":
				if not bool(parsed.get("accepted", false)):
					_finish_client(false, str(parsed.get("message", "Pairing rejected by the hub.")))
					return
				if not _save_pending_hub_pairing():
					_send_client_commit(false)
					_finish_client(false, "Could not save paired hub details locally.")
					return
				_send_client_commit(true)
			"pair_complete":
				var accepted := bool(parsed.get("accepted", false))
				if not accepted:
					_remove_pending_hub_pairing()
				elif not _mark_client_hub_paired():
					_finish_client(false, "The hub accepted pairing, but this device could not finalize its local record.", true)
					return
				_finish_client(accepted, str(parsed.get("message", "Pairing failed.")))
				return
			_:
				_finish_client(false, "The hub sent an invalid pairing response.")
				return
	if _client_peer != null:
		var connection_status := _client_peer.get_connection_status()
		if connection_status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_finish_client(false, "TLS WebSocket connection failed or the hub disconnected.")
		elif Time.get_ticks_msec() > _connection_deadline:
			_finish_client(false, "Timed out waiting for the hub pairing response.")


func _send_client_request() -> void:
	if _client_peer == null or _client_request_sent:
		return
	_client_request_sent = true
	_client_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	var error := _client_peer.put_packet(JSON.stringify(_client_request).to_utf8_buffer())
	if error != OK:
		_finish_client(false, "Could not send the pairing request (%s)." % error_string(error))


func complete_hub_pairing(peer_id: int, accepted: bool, message: String = "") -> void:
	if _hub_peer == null or peer_id != _pending_peer_id:
		return
	_pending_peer_id = 0
	_pending_pairing_deadline = 0
	_pending_device.clear()
	_pending_commit_received = false
	_hub_approved_pending = false
	_send_hub_message(peer_id, {
		"protocol": PAIR_PROTOCOL,
		"type": "pair_complete",
		"accepted": accepted,
		"message": message.substr(0, 160)
	})
	if not accepted:
		_hub_peer.disconnect_peer(peer_id, true)


func _send_client_commit(storage_ready: bool) -> void:
	if _client_peer == null:
		return
	_client_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	var error := _client_peer.put_packet(JSON.stringify({
		"protocol": PAIR_PROTOCOL,
		"type": "pair_commit",
		"client_storage_ready": storage_ready
	}).to_utf8_buffer())
	if error != OK:
		_finish_client(false, "Could not confirm local pairing storage (%s)." % error_string(error))


func _save_pending_hub_pairing() -> bool:
	var file := FileAccess.open(PAIRED_HUB_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save paired hub details: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({
		"version": 1,
		"state": "pairing_pending",
		"hub_address": _client_address,
		"hub_port": _client_port,
		"certificate": _client_certificate_pem,
		"device_id": _client_device_id,
		"pairing_started_at": Time.get_datetime_string_from_system(true)
	}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("Could not finish saving paired hub details: %s" % error_string(write_error))
		return false
	return true


func _mark_client_hub_paired() -> bool:
	var file := FileAccess.open(PAIRED_HUB_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not read the pending paired hub record.")
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or str(parsed.get("device_id", "")) != _client_device_id:
		push_error("The pending paired hub record is invalid; refusing to finalize it.")
		return false
	parsed["state"] = "paired"
	parsed["paired_at"] = Time.get_datetime_string_from_system(true)
	var write_file := FileAccess.open(PAIRED_HUB_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("Could not finalize the local paired hub record.")
		return false
	write_file.store_string(JSON.stringify(parsed, "\t") + "\n")
	write_file.flush()
	var write_error := write_file.get_error()
	write_file.close()
	if write_error != OK:
		push_error("Could not finish finalizing the local paired hub record: %s" % error_string(write_error))
		return false
	return true


func _remove_pending_hub_pairing() -> void:
	if FileAccess.file_exists(PAIRED_HUB_PATH):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(PAIRED_HUB_PATH))
		if error != OK:
			push_error("Could not remove rejected paired hub details: %s" % error_string(error))


func _load_or_create_client_id() -> String:
	if FileAccess.file_exists(CLIENT_ID_PATH):
		var read_file := FileAccess.open(CLIENT_ID_PATH, FileAccess.READ)
		if read_file == null:
			push_error("Could not read the local ANNA device ID.")
			return ""
		var saved_id := read_file.get_as_text().strip_edges()
		read_file.close()
		if not _is_valid_device_id(saved_id):
			push_error("The saved ANNA device ID is malformed; refusing to replace it automatically.")
			return ""
		return saved_id
	var random_bytes := _crypto.generate_random_bytes(16)
	if random_bytes.size() != 16:
		push_error("Could not generate cryptographically secure ANNA device ID bytes.")
		return ""
	var device_id := random_bytes.hex_encode()
	var write_file := FileAccess.open(CLIENT_ID_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("Could not persist the local ANNA device ID.")
		return ""
	write_file.store_string(device_id + "\n")
	write_file.flush()
	var write_error := write_file.get_error()
	write_file.close()
	if write_error != OK:
		push_error("Could not finish saving the local ANNA device ID: %s" % error_string(write_error))
	return device_id if write_error == OK else ""


func _send_hub_message(peer_id: int, message: Dictionary) -> void:
	if _hub_peer == null:
		return
	_hub_peer.set_target_peer(peer_id)
	var error := _hub_peer.put_packet(JSON.stringify(message).to_utf8_buffer())
	if error != OK:
		push_error("Could not send the hub pairing response: %s" % error_string(error))
		_hub_peer.disconnect_peer(peer_id, true)


func _finish_client(accepted: bool, message: String, preserve_pending_record: bool = false) -> void:
	if _client_peer != null:
		_client_peer.close()
		_client_peer = null
	if not accepted and not preserve_pending_record:
		_remove_pending_hub_pairing()
	_client_request.clear()
	_client_request_sent = false
	pairing_finished.emit(accepted, message)


func _sanitize_capabilities(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var clean := value.strip_edges().substr(0, 64)
		if not clean.is_empty() and not result.has(clean) and result.size() < 32:
			result.append(clean)
	return result


func _is_valid_pair_code(code: String) -> bool:
	if code.length() != 64:
		return false
	var hex_pattern := RegEx.new()
	hex_pattern.compile("^[0-9a-f]{64}$")
	return hex_pattern.search(code.to_lower()) != null


func _is_valid_device_id(device_id: String) -> bool:
	if device_id.length() != 32:
		return false
	var hex_pattern := RegEx.new()
	hex_pattern.compile("^[0-9a-f]{32}$")
	return hex_pattern.search(device_id) != null


func _is_valid_ipv4_address(address: String) -> bool:
	var octets := address.split(".")
	if octets.size() != 4:
		return false
	for octet in octets:
		if not octet.is_valid_int() or int(octet) < 0 or int(octet) > 255:
			return false
	return true


func _is_desktop() -> bool:
	return OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]


func _is_local_bind_address(address: String) -> bool:
	if address in ["0.0.0.0", "127.0.0.1"]:
		return true
	if not IP.get_local_addresses().has(address):
		return false
	var octets := address.split(".")
	if octets.size() != 4:
		return false
	for octet in octets:
		if not octet.is_valid_int() or int(octet) < 0 or int(octet) > 255:
			return false
	var first := int(octets[0])
	var second := int(octets[1])
	return first == 10 or (first == 172 and second >= 16 and second <= 31) or (first == 192 and second == 168)
