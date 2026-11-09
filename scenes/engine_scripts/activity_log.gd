extends CanvasLayer

const LOG_PATH := "user://activity_log.json"
const VISIBLE_EVENT_LIMIT := 200

var _events: Array[Dictionary] = []
var _storage_available := true
var _storage_error := ""
var _overlay: Control
var _history: TextEdit
var _status: Label
var _clear_button: Button
var _clear_confirmation: ConfirmationDialog


func _ready() -> void:
	layer = 11
	_build_ui()
	_load_events()
	_overlay.hide()


func record_event(event_type: String, metadata: Dictionary = {}) -> bool:
	if not _storage_available:
		return false
	var safe_metadata := _sanitize_metadata(metadata)
	var event := {
		"timestamp": Time.get_datetime_string_from_system(true),
		"type": event_type,
		"metadata": safe_metadata
	}
	var updated_events := _events.duplicate(true)
	updated_events.append(event)
	if not _write_events(updated_events):
		return false
	_events = updated_events
	if _overlay.visible:
		_refresh_history()
	return true


func show_log() -> void:
	_status.text = _storage_error
	_refresh_history()
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
	panel.offset_left = 48
	panel.offset_top = 96
	panel.offset_right = -48
	panel.offset_bottom = -96
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.035, 0.04, 0.98)
	style.border_color = Color(0.95, 0.42, 0.18, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.content_margin_left = 24
	style.content_margin_top = 20
	style.content_margin_right = 24
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)

	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "Local activity log"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): _overlay.hide())
	heading.add_child(close_button)

	var privacy_note := Label.new()
	privacy_note.text = "Stored on this device. Event metadata only; journal contents and credentials are not recorded."
	privacy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(privacy_note)

	_history = TextEdit.new()
	_history.editable = false
	_history.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.custom_minimum_size.y = 420
	layout.add_child(_history)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)

	_clear_button = Button.new()
	_clear_button.text = "Clear activity log"
	_clear_button.pressed.connect(_confirm_clear)
	layout.add_child(_clear_button)

	_clear_confirmation = ConfirmationDialog.new()
	_clear_confirmation.title = "Clear local activity log?"
	_clear_confirmation.dialog_text = "This permanently removes the activity log on this device. Continue?"
	_clear_confirmation.confirmed.connect(_clear_log)
	add_child(_clear_confirmation)


func _confirm_clear() -> void:
	_clear_confirmation.popup_centered()


func _clear_log() -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		_set_storage_error("Could not clear the local activity log: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({"version": 1, "events": []}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_storage_error("Could not finish clearing the local activity log: %s" % error_string(write_error))
		return
	_events.clear()
	_storage_available = true
	_storage_error = ""
	_status.text = "Local activity log cleared."
	_refresh_history()


func _load_events() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		_set_storage_error("Could not read the local activity log: %s" % error_string(FileAccess.get_open_error()))
		return
	var contents := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(contents)
	if not parsed is Dictionary or not parsed.get("events", []) is Array:
		_set_storage_error("The local activity log is malformed and was left unchanged.")
		return
	for value in parsed["events"]:
		if not value is Dictionary or not value.has("timestamp") or not value.has("type") or not value.has("metadata") or not value["metadata"] is Dictionary:
			_set_storage_error("The local activity log contains an invalid event and was left unchanged.")
			return
		_events.append({
			"timestamp": str(value["timestamp"]),
			"type": str(value["type"]),
			"metadata": _sanitize_metadata(value["metadata"])
		})


func _write_events(events: Array[Dictionary]) -> bool:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		_set_storage_error("Could not write the local activity log: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"version": 1, "events": events}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_storage_error("Could not finish writing the local activity log: %s" % error_string(write_error))
		return false
	return true


func _sanitize_metadata(metadata: Dictionary) -> Dictionary:
	var safe: Dictionary = {}
	for key in ["request_id", "outcome", "provider", "model", "source_count", "proposal", "command", "service", "reason", "http_status"]:
		if metadata.has(key):
			var value := str(metadata[key]).strip_edges()
			if not value.is_empty():
				safe[key] = value.substr(0, 120)
	return safe


func _refresh_history() -> void:
	var start := maxi(0, _events.size() - VISIBLE_EVENT_LIMIT)
	var lines: Array[String] = []
	for index in range(start, _events.size()):
		var event: Dictionary = _events[index]
		lines.append("%s  %s  %s" % [
			str(event.get("timestamp", "")),
			str(event.get("type", "")),
			JSON.stringify(event.get("metadata", {}))
		])
	_history.text = "\n".join(lines)
	_history.scroll_vertical = _history.get_line_count()


func _set_storage_error(message: String) -> void:
	_storage_available = false
	_storage_error = message
	_status.text = message
	push_error(message)
