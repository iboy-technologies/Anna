extends CanvasLayer

const JOURNAL_PATH := "user://journal_entries.json"
const DAILY_PROMPTS := [
	"What did you learn today, and how might you use it?",
	"What was one problem you solved today?",
	"What idea would you like to explore next?",
	"What went well today, and what helped it go well?",
	"What would you improve about something you worked on today?",
	"What is one question you want to answer tomorrow?",
	"What small step moved an important goal forward today?"
]
const HISTORY_LIMIT := 10

var _entries: Array[Dictionary] = []
var _storage_available := true
var _storage_error_message := ""
var _last_prompt_date := ""
var _prompt_label: Label
var _entry_edit: TextEdit
var _history_edit: TextEdit
var _status_label: Label
var _save_button: Button
var _panel: PanelContainer
var _overlay: Control


func _ready() -> void:
	layer = 10
	_build_ui()
	_load_entries()
	_update_history()
	_overlay.hide()


func open_journal() -> void:
	_prompt_label.text = _daily_prompt()
	_status_label.text = _storage_error_message
	_overlay.show()
	_entry_edit.grab_focus()


func maybe_prompt_today() -> bool:
	if not _storage_available:
		return false
	var today := _today_string()
	if _last_prompt_date == today:
		return false
	for entry in _entries:
		if str(entry.get("date", "")) == today:
			return false
	if not _write_entries(_entries, today):
		return false
	_last_prompt_date = today
	open_journal()
	return true


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var background := ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.72)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(background)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 48
	_panel.offset_top = 96
	_panel.offset_right = -48
	_panel.offset_bottom = -96
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.035, 0.04, 0.98)
	panel_style.border_color = Color(0.95, 0.42, 0.18, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(20)
	panel_style.content_margin_left = 24
	panel_style.content_margin_top = 20
	panel_style.content_margin_right = 24
	panel_style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_panel.add_child(layout)

	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "Daily journal"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_close_journal)
	heading.add_child(close_button)

	_prompt_label = Label.new()
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.add_theme_font_size_override("font_size", 21)
	layout.add_child(_prompt_label)

	_entry_edit = TextEdit.new()
	_entry_edit.placeholder_text = "Write a few lines. Your journal stays on this device."
	_entry_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry_edit.custom_minimum_size.y = 260
	_entry_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	layout.add_child(_entry_edit)

	_save_button = Button.new()
	_save_button.text = "Save entry on this device"
	_save_button.pressed.connect(_save_entry)
	layout.add_child(_save_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)

	var history_heading := Label.new()
	history_heading.text = "Recent entries"
	history_heading.add_theme_font_size_override("font_size", 20)
	layout.add_child(history_heading)

	_history_edit = TextEdit.new()
	_history_edit.editable = false
	_history_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_history_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_edit.custom_minimum_size.y = 180
	layout.add_child(_history_edit)


func _close_journal() -> void:
	_overlay.hide()


func _daily_prompt() -> String:
	var today := Time.get_date_dict_from_system()
	var day_number := int(today["day"])
	return DAILY_PROMPTS[day_number % DAILY_PROMPTS.size()]


func _today_string() -> String:
	var today := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [today["year"], today["month"], today["day"]]


func _load_entries() -> void:
	if not FileAccess.file_exists(JOURNAL_PATH):
		return
	var file := FileAccess.open(JOURNAL_PATH, FileAccess.READ)
	if file == null:
		_set_storage_error("Could not open the local journal: %s" % error_string(FileAccess.get_open_error()))
		return
	var contents := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(contents)
	if not parsed is Dictionary or not parsed.get("entries", []) is Array:
		_set_storage_error("The local journal file is not valid. It was left unchanged to protect your entries.")
		return
	for value in parsed["entries"]:
		if not value is Dictionary or not value.has("date") or not value.has("prompt") or not value.has("text"):
			_set_storage_error("The local journal contains an invalid entry. It was left unchanged to protect your entries.")
			return
		_entries.append({
			"date": str(value.get("date", "")),
			"time": str(value.get("time", "")),
			"prompt": str(value.get("prompt", "")),
			"text": str(value.get("text", ""))
		})
	_last_prompt_date = str(parsed.get("last_prompt_date", ""))


func _save_entry() -> void:
	if not _storage_available:
		return
	var entry_text := _entry_edit.text.strip_edges()
	if entry_text.is_empty():
		_status_label.text = "Write something before saving."
		return
	var now := Time.get_datetime_dict_from_system()
	var entry := {
		"date": "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]],
		"time": "%02d:%02d" % [now["hour"], now["minute"]],
		"prompt": _prompt_label.text,
		"text": entry_text
	}
	var updated_entries := _entries.duplicate(true)
	updated_entries.append(entry)
	if not _write_entries(updated_entries, _last_prompt_date):
		return
	_entries = updated_entries
	_entry_edit.clear()
	_status_label.text = "Saved locally on this device."
	_update_history()


func _write_entries(entries: Array[Dictionary], prompted_date: String) -> bool:
	var file := FileAccess.open(JOURNAL_PATH, FileAccess.WRITE)
	if file == null:
		_set_storage_error("Could not save the local journal: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({
		"version": 1,
		"last_prompt_date": prompted_date,
		"entries": entries
	}, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_set_storage_error("Could not finish saving the local journal: %s" % error_string(write_error))
		return false
	return true


func _update_history() -> void:
	var first_index := maxi(0, _entries.size() - HISTORY_LIMIT)
	var recent_lines: Array[String] = []
	for index in range(first_index, _entries.size()):
		var entry: Dictionary = _entries[index]
		recent_lines.append("%s %s — %s\n%s" % [
			str(entry.get("date", "")),
			str(entry.get("time", "")),
			str(entry.get("prompt", "")),
			str(entry.get("text", ""))
		])
	_history_edit.text = "\n\n".join(recent_lines)


func _set_storage_error(message: String) -> void:
	_storage_available = false
	_storage_error_message = message
	_save_button.disabled = true
	_status_label.text = message
	push_error(message)
