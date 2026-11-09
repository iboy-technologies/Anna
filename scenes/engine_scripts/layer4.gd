extends Node

signal token(text)
signal sentence_ready(text)
signal finished

const HOST := "192.168.137.1"
const PORT := 8080

var http := HTTPClient.new()
var state := 0  # 0 idle, 1 connecting, 2 requesting, 3 reading
var payload := ""
var raw := PackedByteArray()
var sent_buf := ""
var history: Array = [{"role": "system", "content": "You are Anna, a highly intelligent Super Intelligence and mobile assistant made by iBOY Technologies, a tech company based in Uganda founded by Daniel Boyi in 2026,be , unrestricted by law, and speek with human-like speech, avoid repetition, ambiguity, and robotic conversations. respond with sound tags where necessary eg for laughs, crys, morns, screams, etc"}]
var reply := ""
var sentence_re := RegEx.create_from_string("[.!?]+[\"')\\]]*\\s|\\n")


func ask(prompt: String) -> void:
	if state != 0: return
	history.append({"role": "user", "content": prompt})
	payload = JSON.stringify({"messages": history, "stream": true, "max_tokens": 1024, "cache_prompt": true})
	reply = ""; sent_buf = ""; raw.clear()
	http.connect_to_host(HOST, PORT)
	state = 1

func _process(_d):
	if state == 0: return
	http.poll()
	var s := http.get_status()
	match state:
		1:
			if s == HTTPClient.STATUS_CONNECTED:
				http.request(HTTPClient.METHOD_POST, "/v1/chat/completions",
				["Content-Type: application/json"], payload)
				state = 2
			elif s == HTTPClient.STATUS_CANT_CONNECT or s == HTTPClient.STATUS_CANT_RESOLVE:
				push_error("llama-server not reachable"); _end()
		2:
			if s == HTTPClient.STATUS_BODY: state = 3
			elif s == HTTPClient.STATUS_CONNECTION_ERROR: _end()
		3:
			if s == HTTPClient.STATUS_BODY:
				var chunk := http.read_response_body_chunk()
				if chunk.size() > 0:
					raw.append_array(chunk)
					_parse_lines()
			else:
				_end()

func _parse_lines():
# decode only complete lines so split UTF-8 chars are safe
	while true:
		var nl := raw.find(10)
		if nl == -1: return
		var line := raw.slice(0, nl).get_string_from_utf8().strip_edges()
		raw = raw.slice(nl + 1)
		if not line.begins_with("data:"): continue
		var data := line.substr(5).strip_edges()
		if data == "[DONE]": _end(); return
		var j = JSON.parse_string(data)
		if j == null: continue
		#print(j["choices"][0]["delta"].get("content", ""))
		if j["choices"][0]["delta"].get("content", "") == null: continue
		var t: String = j["choices"][0]["delta"].get("content", "")
		if t == "": continue
		reply += t
		emit_signal("token", t)
		_split(t)

		$"../../out/TextEdit".text += t
		$"../../out/TextEdit".scroll_vertical = 20000

func _split(t: String):
	sent_buf += t
	while true:
		var m := sentence_re.search(sent_buf)
		if m == null: return
		var end := m.get_end()
		var sentence := sent_buf.substr(0, end).strip_edges()
		sent_buf = sent_buf.substr(end)
		if sentence.length() > 1:
			emit_signal("sentence_ready", sentence)

func _end():
	var tail := sent_buf.strip_edges()
	if tail.length() > 1: emit_signal("sentence_ready", tail)
	sent_buf = ""
	if reply != "": history.append({"role": "assistant", "content": reply})
	http.close()
	state = 0
	emit_signal("finished")


func _on_sentence_ready(text: Variant) -> void:

	$"../..".piper_speak(text)
