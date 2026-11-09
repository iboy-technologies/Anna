extends Control

var setup:bool = false
#var ST:bool = false
var thred:Thread

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if FileAccess.file_exists("user://user.dat"):
		Appstate._ready()
		$"..".call_deferred("prep")
		#print("yoyoyo")
	else:
		$".".show()



func _on_next_pressed() -> void:
	$Panel/Label2.hide()
	var u_name = $Panel/LineEdit.get_text()
	if u_name.is_empty():
		$Panel/Label2.show()
		print("no name")
		return
	var file = FileAccess.open("user://user.dat", FileAccess.WRITE)
	var user_data = {"username":u_name}
	if file.store_var(user_data):
		setup = true
		$AnimationPlayer.stop()
		$ball.show()
		$Panel/AnimationPlayer.play_backwards("get_started")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "get_started" && setup:
		Appstate._ready()
		$ball/AnimationPlayer.play_backwards("change")

func _on_r_animation_finished(anim_name: StringName) -> void:
	if anim_name == "change" && setup:
		thred = Thread.new()
		$Label2.show()
		thred.start($ball/AnimationPlayer.call_deferred_thread_group.bind("play", "loading"))


func _on_get_started_pressed() -> void:
	$Panel/AnimationPlayer.play("get_started")
	$Button.hide()
	$AnimationPlayer.play("login")

#func _physics_process(delta: float) -> void:
#	thred.wait_to_finish()

func _input(event: InputEvent) -> void:
	if event.is_pressed() && event is InputEventKey:
		if event.keycode == KEY_BACK:
			if $Panel.is_visible():
				$Panel/AnimationPlayer.play_backwards("get_started")
			else:
				get_tree().quit()


func _on_animation_player_animation_started(anim_name: StringName) -> void:
	if anim_name == "loading" && setup:
		setup = false
		var timer = Timer.new()
		timer.timeout.connect(loginer)
		add_child(timer)
		timer.set_one_shot(true)
		timer.start(2)

func loginer():
	$AnimationPlayer2.play("logged-in")
	$"..".prep()









#get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")
