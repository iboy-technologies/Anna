extends CanvasLayer

const REGISTRY_PATH := "user://device_registry.json"
const DEVICE_TYPES := ["PC", "Android"]
const FEATURE_SCOPES := ["Device-exclusive", "Shareable"]
const FEATURE_STATES := ["Draft", "Testing", "Tested", "Approved"]
const DevicePairTransportScript = preload("res://scenes/engine_scripts/device_pair_transport.gd")

var _devices: Array[Dictionary] = []
var _features: Array[Dictionary] = []
var _requests: Array[Dictionary] = []
var _household_status_records: Array[Dictionary] = []
var _household_status_requests: Array[Dictionary] = []
var _storage_available := true
var _storage_error := ""
var _overlay: Control
var _device_name: LineEdit
var _device_id: LineEdit
var _device_capabilities: LineEdit
var _device_type: OptionButton
var _device_list: VBoxContainer
var _feature_id: LineEdit
var _feature_version: LineEdit
var _feature_device_id: LineEdit
var _feature_scope: OptionButton
var _feature_types: LineEdit
var _feature_permissions: LineEdit
var _feature_state: OptionButton
var _feature_approval: OptionButton
var _feature_list: VBoxContainer
var _request_capability: LineEdit
var _request_device_id: LineEdit
var _request_intent: LineEdit
var _request_list: VBoxContainer
var _household_name: LineEdit
var _household_status_select: OptionButton
var _household_device_id: LineEdit
var _household_status_list: VBoxContainer
var _household_request_item: LineEdit
var _household_request_device_id: LineEdit
var _household_request_list: VBoxContainer
var _status: Label
var _save_buttons: Array[Button] = []
var _confirm_dialog: ConfirmationDialog
var _permission_dialog: ConfirmationDialog
var _pending_revoke_id := ""
var _pending_permission_device_id := ""
var _pending_permission_capability := ""
var _pair_transport
var _hub_bind_address: LineEdit
var _hub_port: LineEdit
var _hub_status: Label
var _pair_code_display: LineEdit
var _certificate_display: TextEdit
var _hub_wildcard_confirmation: ConfirmationDialog
var _pair_request_dialog: ConfirmationDialog
var _forget_hub_dialog: ConfirmationDialog
var _route_confirmation: ConfirmationDialog
var _pending_route: Dictionary = {}
var _household_request_confirmation: ConfirmationDialog
var _pending_household_status_request: Dictionary = {}
var _client_address: LineEdit
var _client_port: LineEdit
var _client_code: LineEdit
var _client_certificate: TextEdit
var _client_name: LineEdit
var _client_type: OptionButton
var _client_capabilities: LineEdit
var _client_consent: CheckBox
var _pending_pair_device_id := ""
var _pending_pair_peer := 0
var _pending_pair_request: Dictionary = {}


func _ready() -> void:
	layer = 12
	_build_ui()
	_load_registry()
	_refresh_lists()
	_overlay.hide()
	_pair_transport = DevicePairTransportScript.new()
	add_child(_pair_transport)
	_pair_transport.pairing_requested.connect(_on_pairing_requested)
	_pair_transport.pairing_commit_requested.connect(_on_pairing_commit_requested)
	_pair_transport.pairing_aborted.connect(_on_pairing_aborted)
	_pair_transport.pairing_finished.connect(_on_client_pairing_finished)
	_pair_transport.hub_status_changed.connect(_on_hub_status_changed)


func _local_role() -> String:
	if OS.get_name() in ["Windows", "macOS", "Linux", "FreeBSD"]:
		return "PC hub"
	if OS.get_name() == "Android":
		return "Android client"
	return "unsupported platform"


func open_registry() -> void:
	_status.text = _storage_error
	_refresh_lists()
	_overlay.show()


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var background := ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.72)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(background)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 32
	panel.offset_top = 48
	panel.offset_right = -32
	panel.offset_bottom = -48
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.035, 0.04, 0.98)
	style.border_color = Color(0.95, 0.42, 0.18, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.content_margin_left = 20
	style.content_margin_top = 18
	style.content_margin_right = 20
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := Label.new()
	title.text = "Local device & feature registry"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 25)
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): _overlay.hide())
	heading.add_child(close_button)

	var notice := Label.new()
	notice.text = "This installation is the %s. Current multi-device scope is a PC hub and Android client." % _local_role()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(notice)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 16)
	scroll.add_child(sections)

	_add_section_heading(sections, "Device records")
	var device_form := GridContainer.new()
	device_form.columns = 2
	device_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(device_form)
	_add_form_label(device_form, "Display name")
	_device_name = _add_line_edit(device_form, "e.g. My phone")
	_add_form_label(device_form, "Device ID")
	_device_id = _add_line_edit(device_form, "Device ID entered locally")
	_add_form_label(device_form, "Device type")
	_device_type = _add_option_button(device_form, DEVICE_TYPES)
	_add_form_label(device_form, "Known capabilities")
	_device_capabilities = _add_line_edit(device_form, "Comma separated, recorded only")
	var add_device := Button.new()
	add_device.text = "Add unpaired device record"
	add_device.pressed.connect(_add_device_record)
	sections.add_child(add_device)
	_save_buttons.append(add_device)
	_device_list = VBoxContainer.new()
	sections.add_child(_device_list)

	_add_section_heading(sections, "TLS pairing")
	_hub_status = Label.new()
	_hub_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hub_status.text = "Hub transport stopped." if _local_role() == "PC hub" else "This Android device connects as a client." if _local_role() == "Android client" else "Network pairing is disabled on this platform."
	sections.add_child(_hub_status)
	var hub_form := GridContainer.new()
	hub_form.columns = 2
	hub_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(hub_form)
	_add_form_label(hub_form, "Hub bind address (IPv4)")
	_hub_bind_address = _add_line_edit(hub_form, "127.0.0.1 or this PC's LAN IPv4")
	_hub_bind_address.text = "127.0.0.1"
	_add_form_label(hub_form, "Hub port")
	_hub_port = _add_line_edit(hub_form, "8765")
	_hub_port.text = "8765"
	hub_form.visible = _local_role() == "PC hub"
	var hub_buttons := HBoxContainer.new()
	sections.add_child(hub_buttons)
	hub_buttons.visible = _local_role() == "PC hub"
	var start_hub := Button.new()
	start_hub.text = "Start TLS hub"
	start_hub.pressed.connect(_start_hub)
	hub_buttons.add_child(start_hub)
	var stop_hub := Button.new()
	stop_hub.text = "Stop hub"
	stop_hub.pressed.connect(_stop_hub)
	hub_buttons.add_child(stop_hub)
	var make_invitation := Button.new()
	make_invitation.text = "Create one-time invitation"
	make_invitation.pressed.connect(_create_pairing_invitation)
	hub_buttons.add_child(make_invitation)
	var copy_invitation := Button.new()
	copy_invitation.text = "Copy invitation code"
	copy_invitation.pressed.connect(_copy_pairing_invitation)
	hub_buttons.add_child(copy_invitation)
	_pair_code_display = LineEdit.new()
	_pair_code_display.editable = false
	_pair_code_display.placeholder_text = "Invitation code (valid for two minutes)"
	_pair_code_display.visible = _local_role() == "PC hub"
	sections.add_child(_pair_code_display)
	_certificate_display = TextEdit.new()
	_certificate_display.custom_minimum_size.y = 90
	_certificate_display.placeholder_text = "Start the hub to create/load its TLS certificate, then copy this public certificate to the client."
	_certificate_display.editable = false
	_certificate_display.visible = _local_role() == "PC hub"
	sections.add_child(_certificate_display)
	var copy_certificate := Button.new()
	copy_certificate.text = "Copy public hub certificate"
	copy_certificate.pressed.connect(_copy_hub_certificate)
	copy_certificate.visible = _local_role() == "PC hub"
	sections.add_child(copy_certificate)

	_add_section_heading(sections, "Client pairing")
	var client_form := GridContainer.new()
	client_form.columns = 2
	client_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	client_form.visible = _local_role() == "Android client"
	sections.add_child(client_form)
	_add_form_label(client_form, "Hub IPv4 address")
	_client_address = _add_line_edit(client_form, "PC hub address on your LAN")
	_add_form_label(client_form, "Hub port")
	_client_port = _add_line_edit(client_form, "8765")
	_client_port.text = "8765"
	_add_form_label(client_form, "One-time invitation code")
	_client_code = _add_line_edit(client_form, "Paste code from the hub")
	_add_form_label(client_form, "Client display name")
	_client_name = _add_line_edit(client_form, "e.g. My phone")
	_add_form_label(client_form, "Client type")
	_client_type = _add_option_button(client_form, ["Android"])
	_add_form_label(client_form, "Declared capabilities")
	_client_capabilities = _add_line_edit(client_form, "Comma separated; no permissions are granted")
	_add_form_label(client_form, "Pinned hub certificate")
	_client_certificate = TextEdit.new()
	_client_certificate.custom_minimum_size.y = 90
	_client_certificate.placeholder_text = "Paste the public TLS certificate received from your trusted hub."
	client_form.add_child(_client_certificate)
	_client_consent = CheckBox.new()
	_client_consent.text = "I consent to pair this client with the specified ANNA hub."
	_client_consent.visible = _local_role() == "Android client"
	sections.add_child(_client_consent)
	var connect_client := Button.new()
	connect_client.text = "Connect and request pairing"
	connect_client.pressed.connect(_connect_client)
	connect_client.visible = _local_role() == "Android client"
	sections.add_child(connect_client)
	var forget_hub := Button.new()
	forget_hub.text = "Forget saved hub on this device"
	forget_hub.pressed.connect(_confirm_forget_hub)
	forget_hub.visible = _local_role() == "Android client"
	sections.add_child(forget_hub)

	_add_section_heading(sections, "Feature records")
	var feature_form := GridContainer.new()
	feature_form.columns = 2
	feature_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(feature_form)
	_add_form_label(feature_form, "Feature identity")
	_feature_id = _add_line_edit(feature_form, "e.g. local.journal")
	_add_form_label(feature_form, "Version")
	_feature_version = _add_line_edit(feature_form, "e.g. 1.0")
	_add_form_label(feature_form, "Associated device ID")
	_feature_device_id = _add_line_edit(feature_form, "Required for device-exclusive features")
	_add_form_label(feature_form, "Scope")
	_feature_scope = _add_option_button(feature_form, FEATURE_SCOPES)
	_add_form_label(feature_form, "Compatible device types")
	_feature_types = _add_line_edit(feature_form, "Comma separated, e.g. PC, Android")
	_add_form_label(feature_form, "Required permissions")
	_feature_permissions = _add_line_edit(feature_form, "Comma separated, or none")
	_add_form_label(feature_form, "Testing / approval state")
	_feature_state = _add_option_button(feature_form, FEATURE_STATES)
	_add_form_label(feature_form, "Approval record")
	_feature_approval = _add_option_button(feature_form, ["Not reviewed", "Approved (recorded only)", "Rejected"])
	var add_feature := Button.new()
	add_feature.text = "Save feature record"
	add_feature.pressed.connect(_add_feature_record)
	sections.add_child(add_feature)
	_save_buttons.append(add_feature)
	_feature_list = VBoxContainer.new()
	sections.add_child(_feature_list)

	_add_section_heading(sections, "Capability request / route check")
	var route_form := GridContainer.new()
	route_form.columns = 2
	route_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(route_form)
	_add_form_label(route_form, "Capability identity")
	_request_capability = _add_line_edit(route_form, "Capability from the device registry")
	_add_form_label(route_form, "Target device ID")
	_request_device_id = _add_line_edit(route_form, "Exact registered device ID")
	_add_form_label(route_form, "Requested intent")
	_request_intent = _add_line_edit(route_form, "Describe the user-requested capability, not a command")
	var check_route := Button.new()
	check_route.text = "Review and record route request"
	check_route.pressed.connect(_review_route_request)
	sections.add_child(check_route)
	_save_buttons.append(check_route)
	_request_list = VBoxContainer.new()
	sections.add_child(_request_list)

	_add_section_heading(sections, "Household status (manual, status-only)")
	var household_form := GridContainer.new()
	household_form.columns = 2
	household_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(household_form)
	_add_form_label(household_form, "Household item")
	_household_name = _add_line_edit(household_form, "e.g. living-room light")
	_add_form_label(household_form, "Observed status")
	_household_status_select = _add_option_button(household_form, ["Unknown", "Available", "Unavailable", "Attention needed"])
	_add_form_label(household_form, "Associated device ID (optional)")
	_household_device_id = _add_line_edit(household_form, "Local record only")
	var save_household_status := Button.new()
	save_household_status.text = "Save manual status observation"
	save_household_status.pressed.connect(_save_household_status)
	sections.add_child(save_household_status)
	_save_buttons.append(save_household_status)
	_household_status_list = VBoxContainer.new()
	sections.add_child(_household_status_list)

	_add_section_heading(sections, "Household status request (local only)")
	var status_request_form := GridContainer.new()
	status_request_form.columns = 2
	status_request_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(status_request_form)
	_add_form_label(status_request_form, "Household item")
	_household_request_item = _add_line_edit(status_request_form, "Item to check (maximum 80 characters)")
	_add_form_label(status_request_form, "Target device ID (optional)")
	_household_request_device_id = _add_line_edit(status_request_form, "Active registered device, or blank")
	var request_household_status := Button.new()
	request_household_status.text = "Review and record status request"
	request_household_status.pressed.connect(_review_household_status_request)
	sections.add_child(request_household_status)
	_save_buttons.append(request_household_status)
	_household_request_list = VBoxContainer.new()
	sections.add_child(_household_request_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Revoke this device record?"
	_confirm_dialog.dialog_text = "This marks the local device record revoked. It does not send a revoke command to any device."
	_confirm_dialog.confirmed.connect(_revoke_pending_device)
	add_child(_confirm_dialog)

	_permission_dialog = ConfirmationDialog.new()
	_permission_dialog.title = "Record hub-side capability consent?"
	_permission_dialog.confirmed.connect(_confirm_hub_permission)
	add_child(_permission_dialog)

	_hub_wildcard_confirmation = ConfirmationDialog.new()
	_hub_wildcard_confirmation.title = "Listen on all network interfaces?"
	_hub_wildcard_confirmation.dialog_text = "This exposes the TLS pairing port on every network interface. Continue only on a trusted LAN; your firewall still controls reachability."
	_hub_wildcard_confirmation.confirmed.connect(_start_hub_on_confirmed_wildcard)
	add_child(_hub_wildcard_confirmation)

	_pair_request_dialog = ConfirmationDialog.new()
	_pair_request_dialog.title = "Approve client pairing?"
	_pair_request_dialog.confirmed.connect(_approve_pending_pairing)
	_pair_request_dialog.canceled.connect(_reject_pending_pairing)
	add_child(_pair_request_dialog)

	_forget_hub_dialog = ConfirmationDialog.new()
	_forget_hub_dialog.title = "Forget the paired hub on this device?"
	_forget_hub_dialog.dialog_text = "This removes only this device's saved hub address and certificate. It does not revoke the device on the hub; revoke it there separately."
	_forget_hub_dialog.confirmed.connect(_forget_paired_hub)
	add_child(_forget_hub_dialog)

	_route_confirmation = ConfirmationDialog.new()
	_route_confirmation.title = "Record capability route request?"
	_route_confirmation.dialog_text = "This only records a local route check. It will not send or execute a command on another device."
	_route_confirmation.confirmed.connect(_confirm_route_request)
	add_child(_route_confirmation)

	_household_request_confirmation = ConfirmationDialog.new()
	_household_request_confirmation.title = "Save household status request?"
	_household_request_confirmation.confirmed.connect(_confirm_household_status_request)
	add_child(_household_request_confirmation)


func _start_hub() -> void:
	if _local_role() != "PC hub":
		_status.text = "Only a PC desktop build can start the hub."
		return
	if not _hub_port.text.is_valid_int():
		_status.text = "Enter a valid hub port."
		return
	var address := _hub_bind_address.text.strip_edges()
	if address in ["0.0.0.0", "::"]:
		_hub_wildcard_confirmation.popup_centered()
		return
	_start_hub_listener()


func _start_hub_on_confirmed_wildcard() -> void:
	_start_hub_listener()


func _start_hub_listener() -> void:
	if not _storage_available:
		_hub_status.text = "Hub unavailable because the local device registry could not be read or written."
		return
	var error: Error = _pair_transport.start_hub(_hub_bind_address.text.strip_edges(), int(_hub_port.text))
	if error != OK:
		_hub_status.text = "Could not start TLS hub: %s." % error_string(error)
		return
	_certificate_display.text = _pair_transport.get_certificate_text()
	if _certificate_display.text.is_empty():
		_pair_transport.stop_hub()
		_hub_status.text = "Hub certificate could not be loaded; listener stopped."
		return
	_hub_status.text = _pair_transport.get_hub_status() + " Share the public certificate out of band."


func _stop_hub() -> void:
	_pair_transport.stop_hub()
	_pair_code_display.clear()
	_certificate_display.clear()


func _create_pairing_invitation() -> void:
	var code: String = _pair_transport.create_pairing_invitation()
	if code.is_empty():
		_status.text = "The TLS hub must be running and not already handling a pairing."
		return
	_pair_code_display.text = code
	_hub_status.text = "One-time invitation created; it expires in two minutes and is consumed by the first valid request."


func _copy_pairing_invitation() -> void:
	if _pair_code_display.text.is_empty():
		_status.text = "Create an invitation before copying its code."
		return
	DisplayServer.clipboard_set(_pair_code_display.text)
	_status.text = "One-time invitation code copied. Share it through a trusted channel."


func _copy_hub_certificate() -> void:
	if _certificate_display.text.is_empty():
		_status.text = "Start the hub before copying its public certificate."
		return
	DisplayServer.clipboard_set(_certificate_display.text)
	_status.text = "Public certificate copied. Share it through a trusted channel; the private key is never displayed."


func _connect_client() -> void:
	if _local_role() != "Android client":
		_status.text = "Only the Android client build can request pairing with a PC hub."
		return
	if not _storage_available:
		_status.text = "Client pairing is disabled because the local registry is unavailable."
		return
	if not _client_port.text.is_valid_int():
		_status.text = "Enter a valid hub port."
		return
	var caps := _split_values(_client_capabilities.text)
	var error: Error = _pair_transport.connect_client(
		_client_address.text.strip_edges(),
		int(_client_port.text),
		_client_code.text.strip_edges(),
		_client_certificate.text,
		_client_name.text.strip_edges(),
		_client_type.get_item_text(_client_type.selected),
		caps,
		_client_consent.button_pressed
	)
	if error != OK:
		if error == ERR_ALREADY_IN_USE:
			_status.text = "A paired or pending hub is already saved here. Forget it before pairing another hub."
		elif error == ERR_UNAUTHORIZED:
			_status.text = "Check the client consent box before requesting pairing."
		else:
			_status.text = "Could not start client pairing: %s." % error_string(error)
	else:
		_status.text = "Connecting to the hub over pinned-certificate TLS..."


func _on_hub_status_changed(message: String) -> void:
	_hub_status.text = message


func _on_pairing_requested(peer_id: int, request: Dictionary) -> void:
	if not _storage_available:
		_pair_transport.approve_pairing(peer_id, false, "Hub registry storage is unavailable.")
		return
	var device_id := str(request.get("id", ""))
	var index := _find_device(device_id)
	if index >= 0 and str(_devices[index].get("state", "")) in ["paired", "revoked", "pairing_pending"]:
		_pair_transport.approve_pairing(peer_id, false, "This client is already paired or locally revoked.")
		_status.text = "Rejected pairing for an already paired or revoked device ID."
		return
	_pending_pair_device_id = device_id
	_pending_pair_peer = peer_id
	_pending_pair_request = request.duplicate(true)
	_overlay.show()
	_pair_request_dialog.dialog_text = "Allow %s (%s, ID %s) to pair? Respond within 30 seconds. Declared capabilities are metadata only; this grants no permissions or remote actions." % [
		str(request.get("name", "Unknown device")),
		str(request.get("type", "Unknown type")),
		device_id
	]
	_pair_request_dialog.popup_centered()


func _approve_pending_pairing() -> void:
	if _pending_pair_device_id.is_empty():
		return
	if not _storage_available:
		_pair_transport.approve_pairing(_pending_pair_peer, false, "Hub registry storage is unavailable.")
		_pending_pair_peer = 0
		_pending_pair_device_id = ""
		_pending_pair_request.clear()
		return
	var index := _find_device(_pending_pair_device_id)
	if index >= 0 and str(_devices[index].get("state", "")) in ["paired", "revoked", "pairing_pending"]:
		_pair_transport.approve_pairing(_pending_pair_peer, false, "This client cannot be paired.")
		_pending_pair_peer = 0
		_pending_pair_device_id = ""
		_pending_pair_request.clear()
		return
	var updated_devices := _devices.duplicate(true)
	var device: Dictionary = _pending_pair_request.duplicate(true)
	device["role"] = "client"
	device["state"] = "pairing_pending"
	device["registered_at"] = str(_devices[index].get("registered_at", Time.get_datetime_string_from_system(true))) if index >= 0 else Time.get_datetime_string_from_system(true)
	device["permission_grants"] = {}
	if index >= 0:
		updated_devices[index] = device
	else:
		updated_devices.append(device)
	if not _save_registry(updated_devices, _features):
		_pair_transport.approve_pairing(_pending_pair_peer, false, "Could not persist the hub registry.")
		_pending_pair_peer = 0
		_pending_pair_device_id = ""
		_pending_pair_request.clear()
		return
	_devices = updated_devices
	_refresh_lists()
	_pair_transport.approve_pairing(_pending_pair_peer, true, "Hub approved; confirming client storage.")
	_status.text = "Hub consent recorded; waiting for the client to confirm local pairing storage."


func _reject_pending_pairing() -> void:
	var peer_id := _pending_pair_peer
	if peer_id != 0:
		_pair_transport.approve_pairing(peer_id, false, "Pairing declined by the hub user.")
	_pending_pair_peer = 0
	_pending_pair_device_id = ""
	_pending_pair_request.clear()


func _on_pairing_commit_requested(peer_id: int, request: Dictionary) -> void:
	if not _storage_available or str(request.get("id", "")) != _pending_pair_device_id:
		_pair_transport.complete_hub_pairing(peer_id, false, "Hub registry could not confirm this client.")
		_pending_pair_device_id = ""
		_pending_pair_peer = 0
		_pending_pair_request.clear()
		_pair_request_dialog.hide()
		return
	var index := _find_device(_pending_pair_device_id)
	if index < 0 or str(_devices[index].get("state", "")) != "pairing_pending":
		_pair_transport.complete_hub_pairing(peer_id, false, "The pending client record is missing.")
		_pending_pair_device_id = ""
		_pending_pair_peer = 0
		_pending_pair_request.clear()
		return
	var updated_devices := _devices.duplicate(true)
	updated_devices[index]["state"] = "paired"
	updated_devices[index]["paired_at"] = Time.get_datetime_string_from_system(true)
	updated_devices[index]["pairing_method"] = "tls_websocket"
	if _save_registry(updated_devices, _features):
		_devices = updated_devices
		_refresh_lists()
		_pair_transport.complete_hub_pairing(peer_id, true, "Paired. No feature permissions were granted.")
		_status.text = "Client paired over TLS. Capability execution remains disabled."
	else:
		_pair_transport.complete_hub_pairing(peer_id, false, "Could not persist paired state.")
	_pending_pair_device_id = ""
	_pending_pair_peer = 0
	_pending_pair_request.clear()


func _on_pairing_aborted(request: Dictionary) -> void:
	var device_id := str(request.get("id", ""))
	_pair_request_dialog.hide()
	var index := _find_device(device_id)
	if index >= 0 and str(_devices[index].get("state", "")) == "pairing_pending":
		var updated_devices := _devices.duplicate(true)
		updated_devices[index]["state"] = "unpaired"
		updated_devices[index].erase("pairing_method")
		if _save_registry(updated_devices, _features):
			_devices = updated_devices
			_refresh_lists()
			_status.text = "Pairing was interrupted; the hub record remains unpaired."
	_pending_pair_device_id = ""
	_pending_pair_peer = 0
	_pending_pair_request.clear()


func _on_client_pairing_finished(accepted: bool, message: String) -> void:
	_status.text = message
	_client_consent.button_pressed = false
	if accepted:
		_status.text = "Client paired with the hub. " + message


func _confirm_forget_hub() -> void:
	_forget_hub_dialog.popup_centered()


func _forget_paired_hub() -> void:
	var error: Error = _pair_transport.forget_paired_hub()
	if error == OK:
		_status.text = "Saved hub details removed from this device. The hub-side record was not changed."
	elif error == ERR_DOES_NOT_EXIST:
		_status.text = "There is no saved paired hub on this device."
	else:
		_status.text = "Could not remove the saved hub details: %s." % error_string(error)


func _add_section_heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)


func _add_form_label(parent: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _add_line_edit(parent: GridContainer, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _add_option_button(parent: GridContainer, options: Array) -> OptionButton:
	var select := OptionButton.new()
	for option in options:
		select.add_item(str(option))
	parent.add_child(select)
	return select


func _add_device_record() -> void:
	if not _storage_available:
		return
	var name := _device_name.text.strip_edges()
	var device_id := _device_id.text.strip_edges()
	if name.is_empty() or device_id.is_empty():
		_status.text = "Enter both a display name and device ID."
		return
	if _find_device(device_id) >= 0:
		_status.text = "That device ID is already registered."
		return
	var updated_devices := _devices.duplicate(true)
	updated_devices.append({
		"id": device_id,
		"name": name,
		"type": _device_type.get_item_text(_device_type.selected),
		"role": "client",
		"state": "unpaired",
		"registered_at": Time.get_datetime_string_from_system(true),
		"capabilities": _split_values(_device_capabilities.text),
		"permission_grants": {}
	})
	if _save_registry(updated_devices, _features):
		_devices = updated_devices
		_device_name.clear()
		_device_id.clear()
		_device_capabilities.clear()
		_status.text = "Saved as an unpaired local record."
		_refresh_lists()


func _add_feature_record() -> void:
	if not _storage_available:
		return
	var identity := _feature_id.text.strip_edges()
	var version := _feature_version.text.strip_edges()
	if identity.is_empty() or version.is_empty():
		_status.text = "Enter a feature identity and version."
		return
	var scope := _feature_scope.get_item_text(_feature_scope.selected).to_lower()
	var target_device_id := _feature_device_id.text.strip_edges()
	if scope == "device-exclusive" and _find_active_device(target_device_id) < 0:
		_status.text = "Device-exclusive features must reference an active local device record."
		return
	if not target_device_id.is_empty() and _find_active_device(target_device_id) < 0:
		_status.text = "The associated device ID is not an active local device record."
		return
	var updated_features := _features.duplicate(true)
	updated_features.append({
		"identity": identity,
		"version": version,
		"device_id": target_device_id,
		"scope": scope,
		"compatible_device_types": _split_values(_feature_types.text),
		"required_permissions": _split_values(_feature_permissions.text),
		"testing_state": _feature_state.get_item_text(_feature_state.selected).to_lower(),
		"approval_state": _feature_approval.get_item_text(_feature_approval.selected).to_lower(),
		"registered_at": Time.get_datetime_string_from_system(true)
	})
	if _save_registry(_devices, updated_features):
		_features = updated_features
		_feature_id.clear()
		_feature_version.clear()
		_feature_device_id.clear()
		_feature_types.clear()
		_feature_permissions.clear()
		_status.text = "Feature metadata saved. No feature was installed, approved for execution, or shared."
		_refresh_lists()


func _review_route_request() -> void:
	if not _storage_available:
		return
	var capability := _request_capability.text.strip_edges()
	var device_id := _request_device_id.text.strip_edges()
	var intent := _request_intent.text.strip_edges()
	if capability.is_empty() or capability.length() > 64 or device_id.is_empty() or intent.is_empty() or intent.length() > 240:
		_status.text = "Enter a capability, exact target device ID, and a short intent (maximum 240 characters)."
		return
	var route_check := _evaluate_route_request(device_id, capability)
	_pending_route = {
		"capability": capability,
		"device_id": device_id,
		"intent": intent,
		"route_check": route_check
	}
	_route_confirmation.dialog_text = "Save your intent text locally for %s on device %s? Check: %s. This is metadata only; no request will be sent or executed." % [
		capability,
		device_id,
		str(route_check.get("reason", "route unavailable"))
	]
	_route_confirmation.popup_centered()


func _evaluate_route_request(device_id: String, capability: String) -> Dictionary:
	var index := _find_device(device_id)
	if index < 0:
		return {"state": "blocked_unknown_device", "compatible": false, "consented": false, "paired": false, "transport_available": false, "reason": "No matching registered device"}
	var device: Dictionary = _devices[index]
	if str(device.get("state", "")) == "revoked":
		return {"state": "blocked_revoked_device", "compatible": false, "consented": false, "paired": false, "transport_available": false, "reason": "Device record is revoked"}
	var compatible := _device_supports_capability(device, capability)
	if not compatible:
		return {"state": "blocked_incompatible", "compatible": false, "consented": false, "paired": str(device.get("state", "")) == "paired", "transport_available": false, "reason": "Capability is not listed for this device or a compatible feature record"}
	var readiness := _feature_route_readiness(device, capability)
	if not str(readiness.get("state", "")).is_empty():
		return {"state": str(readiness.get("state", "")), "compatible": true, "consented": false, "paired": str(device.get("state", "")) == "paired", "transport_available": false, "reason": str(readiness.get("reason", "Feature is not ready"))}
	var paired := str(device.get("state", "")) == "paired"
	if not paired:
		return {"state": "blocked_unpaired", "compatible": true, "consented": false, "paired": false, "transport_available": false, "reason": "Device is not paired"}
	var grants = device.get("permission_grants", {})
	if not grants is Dictionary:
		return {"state": "blocked_consent", "compatible": true, "consented": false, "paired": true, "transport_available": false, "reason": "Device consent metadata is invalid"}
	var required_consents := _required_capability_consents(device, capability)
	for required_capability in required_consents:
		var grant: Dictionary = grants.get(required_capability, {})
		if not bool(grant.get("hub_approved", false)) or not bool(grant.get("client_approved", false)):
			return {"state": "blocked_consent", "compatible": true, "consented": false, "paired": true, "transport_available": false, "reason": "Both hub and device consent are not recorded for %s" % required_capability}
	return {"state": "blocked_no_live_transport", "compatible": true, "consented": true, "paired": true, "transport_available": false, "reason": "No authenticated live client session or execution protocol is available"}


func _required_capability_consents(device: Dictionary, capability: String) -> Array[String]:
	var required: Array[String] = [capability]
	for feature in _features:
		if str(feature.get("identity", "")) != capability or not _feature_applies_to_device(feature, device):
			continue
		var permissions = feature.get("required_permissions", [])
		if permissions is Array:
			for permission in permissions:
				var name := str(permission).strip_edges()
				if not name.is_empty() and not required.has(name):
					required.append(name)
	return required


func _feature_route_readiness(device: Dictionary, capability: String) -> Dictionary:
	for feature in _features:
		if str(feature.get("identity", "")) != capability or not _feature_applies_to_device(feature, device):
			continue
		var testing_state := str(feature.get("testing_state", "draft")).to_lower()
		if testing_state not in ["tested", "approved"]:
			return {"state": "blocked_feature_not_tested", "reason": "Feature testing state is %s" % testing_state}
		var approval_state := str(feature.get("approval_state", "not reviewed")).to_lower()
		if not approval_state.begins_with("approved"):
			return {"state": "blocked_feature_unapproved", "reason": "Feature approval is not recorded"}
	return {}


func _feature_applies_to_device(feature: Dictionary, device: Dictionary) -> bool:
	var feature_device_id := str(feature.get("device_id", ""))
	if not feature_device_id.is_empty() and feature_device_id != str(device.get("id", "")):
		return false
	var compatible_types = feature.get("compatible_device_types", [])
	if compatible_types is not Array:
		return false
	if not compatible_types.is_empty():
		return compatible_types.has(str(device.get("type", "")))
	var device_capabilities = device.get("capabilities", [])
	return feature_device_id == str(device.get("id", "")) or (device_capabilities is Array and device_capabilities.has(str(feature.get("identity", ""))))


func _device_supports_capability(device: Dictionary, capability: String) -> bool:
	var capabilities = device.get("capabilities", [])
	if capabilities is Array and capabilities.has(capability):
		return true
	for feature in _features:
		if str(feature.get("identity", "")) == capability and _feature_applies_to_device(feature, device):
			return true
	return false


func _confirm_route_request() -> void:
	if _pending_route.is_empty() or not _storage_available:
		return
	var updated_requests := _requests.duplicate(true)
	var request_id := "route-%s-%d" % [Time.get_datetime_string_from_system().replace(":", "").replace("-", ""), Time.get_ticks_msec()]
	updated_requests.append({
		"id": request_id,
		"capability": str(_pending_route.get("capability", "")),
		"device_id": str(_pending_route.get("device_id", "")),
		"intent": str(_pending_route.get("intent", "")),
		"route_check": _pending_route.get("route_check", {}).duplicate(true),
		"state": "not_sent",
		"created_at": Time.get_datetime_string_from_system(true)
	})
	if _save_registry(_devices, _features, updated_requests, _household_status_records):
		_requests = updated_requests
		var check: Dictionary = _pending_route.get("route_check", {})
		_status.text = "Request %s saved locally. %s; it was not sent or executed." % [request_id, str(check.get("reason", "No live route"))]
		_request_capability.clear()
		_request_intent.clear()
		_refresh_lists()
	_pending_route.clear()


func _save_household_status() -> void:
	if not _storage_available:
		return
	var item_name := _household_name.text.strip_edges()
	var device_id := _household_device_id.text.strip_edges()
	if item_name.is_empty() or item_name.length() > 80:
		_status.text = "Enter a household item name no longer than 80 characters."
		return
	if not device_id.is_empty():
		var device_index := _find_device(device_id)
		if device_index < 0 or str(_devices[device_index].get("state", "")) == "revoked":
			_status.text = "Choose an active registered device or leave the device ID blank."
			return
	var updated_status := _household_status_records.duplicate(true)
	updated_status.append({
		"item": item_name,
		"status": _household_status_select.get_item_text(_household_status_select.selected).to_lower().replace(" ", "_"),
		"device_id": device_id,
		"source": "manual_observation",
		"observed_at": Time.get_datetime_string_from_system(true)
	})
	if _save_registry(_devices, _features, _requests, updated_status):
		_household_status_records = updated_status
		_household_name.clear()
		_household_device_id.clear()
		_status.text = "Manual status saved locally; no appliance was queried or controlled."
		_refresh_lists()


func _review_household_status_request() -> void:
	if not _storage_available:
		return
	var item_name := _household_request_item.text.strip_edges()
	var device_id := _household_request_device_id.text.strip_edges()
	if item_name.is_empty() or item_name.length() > 80:
		_status.text = "Enter a household item name no longer than 80 characters."
		return
	var route_check := _evaluate_household_status_request(device_id)
	if not device_id.is_empty() and str(route_check.get("state", "")) in ["blocked_unknown_device", "blocked_revoked_device"]:
		_status.text = str(route_check.get("reason", "Choose an active registered device or leave the device ID blank."))
		return
	_pending_household_status_request = {
		"item": item_name,
		"device_id": device_id,
		"route_check": route_check
	}
	var target_description := " on device %s" % device_id if not device_id.is_empty() else ""
	_household_request_confirmation.dialog_text = "Save a local status request for %s%s? %s. This app will not send it or query an appliance." % [
		item_name,
		target_description,
		str(route_check.get("reason", "No live status route is available"))
	]
	_household_request_confirmation.popup_centered()


func _evaluate_household_status_request(device_id: String) -> Dictionary:
	if device_id.is_empty():
		return {
			"state": "blocked_no_target",
			"transport_available": false,
			"reason": "No target device was selected; no appliance status adapter is available"
		}
	var index := _find_device(device_id)
	if index < 0:
		return {
			"state": "blocked_unknown_device",
			"transport_available": false,
			"reason": "No matching registered device"
		}
	var device: Dictionary = _devices[index]
	if str(device.get("state", "")) == "revoked":
		return {
			"state": "blocked_revoked_device",
			"transport_available": false,
			"reason": "Target device record is revoked"
		}
	if str(device.get("state", "")) != "paired":
		return {
			"state": "blocked_unpaired",
			"transport_available": false,
			"reason": "Target device is not paired"
		}
	return {
		"state": "blocked_no_live_status_transport",
		"transport_available": false,
		"reason": "Pairing is enrollment only; no persistent authenticated client session or appliance status adapter is available"
	}


func _confirm_household_status_request() -> void:
	if _pending_household_status_request.is_empty() or not _storage_available:
		return
	var updated_status_requests := _household_status_requests.duplicate(true)
	var request_id := "status-%s-%d" % [Time.get_datetime_string_from_system().replace(":", "").replace("-", ""), Time.get_ticks_msec()]
	var device_id := str(_pending_household_status_request.get("device_id", ""))
	var route_check := _evaluate_household_status_request(device_id)
	updated_status_requests.append({
		"id": request_id,
		"item": str(_pending_household_status_request.get("item", "")),
		"device_id": device_id,
		"route_check": route_check,
		"state": "not_sent",
		"created_at": Time.get_datetime_string_from_system(true)
	})
	if _save_registry(_devices, _features, _requests, _household_status_records, updated_status_requests):
		_household_status_requests = updated_status_requests
		_status.text = "Status request %s saved locally. %s; it was not sent and no status was queried." % [
			request_id,
			str(route_check.get("reason", "No live status route is available"))
		]
		_household_request_item.clear()
		_household_request_device_id.clear()
		_refresh_lists()
	_pending_household_status_request.clear()


func _split_values(value: String) -> Array[String]:
	var result: Array[String] = []
	for part in value.split(","):
		var clean := part.strip_edges()
		if not clean.is_empty() and not result.has(clean):
			result.append(clean)
	return result


func _join_values(values: Array) -> String:
	var strings: Array[String] = []
	for value in values:
		strings.append(str(value))
	return ", ".join(strings)


func _refresh_lists() -> void:
	if _device_list == null:
		return
	for child in _device_list.get_children():
		child.queue_free()
	for device in _devices:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s — %s (%s), %s; capabilities: %s" % [
			str(device.get("name", "")),
			"%s client" % str(device.get("type", "")),
			str(device.get("id", "")),
			str(device.get("state", "unpaired")),
			_join_values(device.get("capabilities", []))
		]
		row.add_child(label)
		if str(device.get("state", "")) != "revoked":
			var revoke := Button.new()
			revoke.text = "Revoke record"
			revoke.pressed.connect(_confirm_revoke.bind(str(device.get("id", ""))))
			row.add_child(revoke)
		_device_list.add_child(row)
		var capabilities: Array = device.get("capabilities", [])
		var grants: Dictionary = device.get("permission_grants", {})
		var paired := str(device.get("state", "")) == "paired"
		var permission_capabilities: Array[String] = []
		for capability_value in capabilities:
			var advertised_capability := str(capability_value)
			if not permission_capabilities.has(advertised_capability):
				permission_capabilities.append(advertised_capability)
		for feature in _features:
			var feature_identity := str(feature.get("identity", ""))
			if not _feature_applies_to_device(feature, device):
				continue
			for required_capability in _required_capability_consents(device, feature_identity):
				if not permission_capabilities.has(required_capability):
					permission_capabilities.append(required_capability)
		for capability in permission_capabilities:
			var grant: Dictionary = grants.get(capability, {})
			var permission_row := HBoxContainer.new()
			var permission_label := Label.new()
			permission_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var permission_state := "device revoked" if str(device.get("state", "")) == "revoked" else _permission_state_label(grant, paired)
			permission_label.text = "%s — %s" % [capability, permission_state]
			permission_row.add_child(permission_label)
			if str(device.get("state", "")) != "revoked":
				var consent_button := Button.new()
				consent_button.text = "Remove hub consent" if bool(grant.get("hub_approved", false)) else "Approve on hub"
				consent_button.pressed.connect(_ask_hub_permission.bind(str(device.get("id", "")), capability, not bool(grant.get("hub_approved", false))))
				permission_row.add_child(consent_button)
			_device_list.add_child(permission_row)
	for child in _feature_list.get_children():
		child.queue_free()
	for feature in _features:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s v%s — %s; device: %s; compatible: %s; permissions: %s; test: %s; approval: %s" % [
			str(feature.get("identity", "")),
			str(feature.get("version", "")),
			str(feature.get("scope", "")),
			str(feature.get("device_id", "any")),
			_join_values(feature.get("compatible_device_types", [])),
			_join_values(feature.get("required_permissions", [])),
			str(feature.get("testing_state", "draft")),
			str(feature.get("approval_state", "not reviewed"))
		]
		_feature_list.add_child(label)
	for child in _request_list.get_children():
		child.queue_free()
	for request in _requests:
		var request_label := Label.new()
		request_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var route_check: Dictionary = request.get("route_check", {})
		request_label.text = "%s → %s: %s (%s; %s; not sent)" % [
			str(request.get("capability", "")),
			str(request.get("device_id", "")),
			str(request.get("intent", "")),
			str(request.get("state", "not_sent")),
			str(route_check.get("reason", "route unavailable"))
		]
		_request_list.add_child(request_label)
	for child in _household_status_list.get_children():
		child.queue_free()
	for record in _household_status_records:
		var status_label := Label.new()
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.text = "%s — %s; source: manual; device: %s; observed: %s (not live)" % [
			str(record.get("item", "")),
			str(record.get("status", "unknown")),
			str(record.get("device_id", "not assigned")),
			str(record.get("observed_at", ""))
		]
		_household_status_list.add_child(status_label)
	for child in _household_request_list.get_children():
		child.queue_free()
	for request in _household_status_requests:
		var request_label := Label.new()
		request_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var route_check: Dictionary = request.get("route_check", {})
		var target_device_id := str(request.get("device_id", ""))
		if target_device_id.is_empty():
			target_device_id = "not specified"
		request_label.text = "%s — device: %s; %s; %s; not sent" % [
			str(request.get("item", "")),
			target_device_id,
			str(request.get("state", "not_sent")),
			str(route_check.get("reason", "No live status route is available"))
		]
		_household_request_list.add_child(request_label)


func _confirm_revoke(device_id: String) -> void:
	_pending_revoke_id = device_id
	_confirm_dialog.popup_centered()


func _ask_hub_permission(device_id: String, capability: String, approved: bool) -> void:
	_pending_permission_device_id = device_id
	_pending_permission_capability = capability
	_permission_dialog.title = "Record hub-side consent?" if approved else "Remove hub-side consent?"
	_permission_dialog.dialog_text = "Record the hub's consent for %s? This is not a device permission grant or executable authorization; client consent and authenticated pairing are still required." % capability if approved else "Remove the hub's local consent for %s?" % capability
	_permission_dialog.set_meta("pending_approved", approved)
	_permission_dialog.popup_centered()


func _confirm_hub_permission() -> void:
	var index := _find_active_device(_pending_permission_device_id)
	if index < 0:
		_status.text = "The active client record no longer exists."
		return
	var updated_devices := _devices.duplicate(true)
	var grants: Dictionary = updated_devices[index].get("permission_grants", {}).duplicate(true)
	var grant: Dictionary = grants.get(_pending_permission_capability, {}).duplicate(true)
	var approved := bool(_permission_dialog.get_meta("pending_approved", false))
	grant["hub_approved"] = approved
	grant["client_approved"] = false
	grant["state"] = "pending_client_consent" if approved else "not_granted"
	if approved:
		grant["hub_approved_at"] = Time.get_datetime_string_from_system(true)
	else:
		grant.erase("hub_approved_at")
	grants[_pending_permission_capability] = grant
	updated_devices[index]["permission_grants"] = grants
	if _save_registry(updated_devices, _features):
		_devices = updated_devices
		_status.text = "Hub-side consent metadata saved; the capability remains inactive until client consent and secure pairing."
		_refresh_lists()


func _permission_state_label(grant: Dictionary, paired: bool) -> String:
	if not bool(grant.get("hub_approved", false)):
		return "not granted"
	if not bool(grant.get("client_approved", false)):
		return "hub consent recorded; awaiting client consent"
	if not paired:
		return "both consents recorded; pairing required"
	return "consent recorded; execution not implemented"


func _revoke_pending_device() -> void:
	if not _storage_available:
		return
	var index := _find_device(_pending_revoke_id)
	if index < 0:
		_status.text = "The device record no longer exists."
		return
	var updated_devices := _devices.duplicate(true)
	updated_devices[index]["state"] = "revoked"
	updated_devices[index]["revoked_at"] = Time.get_datetime_string_from_system(true)
	var grants: Dictionary = updated_devices[index].get("permission_grants", {}).duplicate(true)
	for capability in grants:
		var grant: Dictionary = grants[capability]
		grant["hub_approved"] = false
		grant["client_approved"] = false
		grant["state"] = "revoked"
		grants[capability] = grant
	updated_devices[index]["permission_grants"] = grants
	if _save_registry(updated_devices, _features):
		_devices = updated_devices
		_status.text = "Device record revoked locally. No remote device was contacted."
		_refresh_lists()


func _find_device(device_id: String) -> int:
	for index in _devices.size():
		if str(_devices[index].get("id", "")) == device_id:
			return index
	return -1


func _find_active_device(device_id: String) -> int:
	var index := _find_device(device_id)
	if index < 0 or str(_devices[index].get("state", "")) == "revoked":
		return -1
	return index


func _load_registry() -> void:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		_set_storage_error("Could not read the local device registry: %s" % error_string(FileAccess.get_open_error()))
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("devices", []) is Array or not parsed.get("features", []) is Array or not parsed.get("requests", []) is Array or not parsed.get("household_status", []) is Array or not parsed.get("household_status_requests", []) is Array:
		_set_storage_error("The local device registry is malformed and was left unchanged.")
		return
	var interrupted_pairing := false
	for device in parsed["devices"]:
		if not device is Dictionary or not device.has("id") or not device.has("name") or not device.has("type") or not device.has("state"):
			_set_storage_error("The local device registry contains an invalid device record and was left unchanged.")
			return
		var normalized_device: Dictionary = device.duplicate(true)
		normalized_device["role"] = str(normalized_device.get("role", "client"))
		if str(normalized_device.get("state", "")) == "pairing_pending":
			normalized_device["state"] = "unpaired"
			normalized_device.erase("pairing_method")
			interrupted_pairing = true
		var capabilities = normalized_device.get("capabilities", [])
		var grants = normalized_device.get("permission_grants", {})
		if not capabilities is Array or not grants is Dictionary:
			_set_storage_error("The local device registry contains invalid capability permissions and was left unchanged.")
			return
		for capability in capabilities:
			if not capability is String:
				_set_storage_error("The local device registry contains an invalid capability and was left unchanged.")
				return
		for capability in grants:
			if not grants[capability] is Dictionary:
				_set_storage_error("The local device registry contains an invalid permission record and was left unchanged.")
				return
			for consent_key in ["hub_approved", "client_approved"]:
				if grants[capability].has(consent_key) and typeof(grants[capability][consent_key]) != TYPE_BOOL:
					_set_storage_error("The local device registry contains invalid consent state and was left unchanged.")
					return
		_devices.append(normalized_device)
	for feature in parsed["features"]:
		if not feature is Dictionary or not feature.has("identity") or not feature.has("version") or not feature.has("scope") or not feature.has("testing_state"):
			_set_storage_error("The local registry contains an invalid feature record and was left unchanged.")
			return
		_features.append(feature)
	for request in parsed.get("requests", []):
		if not request is Dictionary or not request.has("id") or not request.has("device_id") or not request.has("capability") or not request.has("intent") or not request.has("state") or str(request.get("state", "")) != "not_sent" or not request.get("route_check", {}) is Dictionary:
			_set_storage_error("The local registry contains an invalid capability request and was left unchanged.")
			return
		var route_check: Dictionary = request.get("route_check", {})
		if typeof(route_check.get("transport_available", false)) != TYPE_BOOL or bool(route_check.get("transport_available", false)) or str(request.get("intent", "")).length() > 240:
			_set_storage_error("The local registry contains an invalid or executable capability request and was left unchanged.")
			return
		_requests.append(request)
	for record in parsed.get("household_status", []):
		if not record is Dictionary or not record.has("item") or str(record.get("item", "")).is_empty() or str(record.get("item", "")).length() > 80 or not record.has("status") or str(record.get("status", "")) not in ["unknown", "available", "unavailable", "attention_needed"] or str(record.get("source", "")) != "manual_observation":
			_set_storage_error("The local registry contains an invalid household status record and was left unchanged.")
			return
		_household_status_records.append(record)
	for request in parsed.get("household_status_requests", []):
		if not request is Dictionary or not request.has("id") or typeof(request.get("id", null)) != TYPE_STRING or str(request.get("id", "")).is_empty() or not request.has("item") or typeof(request.get("item", null)) != TYPE_STRING or str(request.get("item", "")).is_empty() or str(request.get("item", "")).length() > 80 or not request.has("device_id") or typeof(request.get("device_id", null)) != TYPE_STRING or str(request.get("device_id", "")).length() > 128 or not request.has("state") or str(request.get("state", "")) != "not_sent" or not request.get("route_check", {}) is Dictionary:
			_set_storage_error("The local registry contains an invalid household status request and was left unchanged.")
			return
		var route_check: Dictionary = request.get("route_check", {})
		if typeof(route_check.get("transport_available", false)) != TYPE_BOOL or bool(route_check.get("transport_available", false)) or typeof(route_check.get("reason", null)) != TYPE_STRING or str(route_check.get("reason", "")).is_empty():
			_set_storage_error("The local registry contains an executable household status request and was left unchanged.")
			return
		_household_status_requests.append(request)
	if interrupted_pairing and not _save_registry(_devices, _features):
		return


func _save_registry(devices: Array[Dictionary], features: Array[Dictionary], requests = null, household_status = null, household_status_requests = null) -> bool:
	var saved_requests = _requests if requests == null else requests
	var saved_household_status = _household_status_records if household_status == null else household_status
	var saved_household_status_requests = _household_status_requests if household_status_requests == null else household_status_requests
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if file == null:
		_set_storage_error("Could not save the local device registry: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({
		"version": 3,
		"devices": devices,
		"features": features,
		"requests": saved_requests,
		"household_status": saved_household_status,
		"household_status_requests": saved_household_status_requests
	}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_storage_error("Could not finish saving the local device registry: %s" % error_string(write_error))
		return false
	return true


func _set_storage_error(message: String) -> void:
	_storage_available = false
	_status.text = message
	for button in _save_buttons:
		button.disabled = true
	push_error(message)
