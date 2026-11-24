extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var lobby = load("res://ui/main_menu.tscn").instantiate()
	root.add_child(lobby)
	var size_arg := OS.get_cmdline_user_args()[-1]
	var expected := size_arg.to_int() if size_arg.length() == 1 else 4
	var host := OS.get_cmdline_user_args().has("host")
	lobby.get_node("Center/Menu/Port").value = 39467
	if host:
		lobby.host_room()
		if OS.get_cmdline_user_args().has("stairs"):
			lobby.get_node("Center/Menu/Map").item_selected.emit(1)
		print("ROOM ", lobby.room_code)
	else:
		lobby.get_node("Center/Menu/Address").text = OS.get_cmdline_user_args()[0]
		lobby.join_room()
	var deadline := Time.get_ticks_msec() + 9000
	var walked := false
	var sent := false
	var voted := false
	var saw_chain := false
	var release_at := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if lobby.members.size() != expected:
			continue
		if not sent:
			lobby.toggle_ready()
			sent = true
		if host and not lobby.arena and lobby.members.values().all(func(member): return member.ready):
			lobby.start_match()
		if lobby.arena and not host and not walked:
			var a = lobby.arena
			var slot: int = a.local_slot
			var start: Vector3 = a.body.spawn.origin + a.body.slots[slot]
			var key := InputEventKey.new()
			key.physical_keycode = KEY_D
			var delta_pos: Vector3 = a.walkers[slot].position - start
			walked = Vector2(delta_pos.x, delta_pos.z).length() > 0.35
			key.pressed = not walked
			Input.parse_input_event(key)
			if walked:
				print("PASS guest displays horizontal movement")
		if lobby.arena and not voted and (host or walked):
			if OS.get_cmdline_user_args().has("stairs"):
				var course = lobby.arena.get_node("SkyCourse")
				assert(course.mines.size() == 48 and course.vents.size() == 12)
				print("Layout ", course.layout_seed, " ", course.mines[-1].position)
				var vent: Node3D = course.vents[0]
				assert(course.wind_at(vent.position + vent.basis.y).dot(vent.basis.y) > 0)
			voted = true
			if host:
				lobby.arena.act(0, true)
			else:
				lobby.arena.action.rpc_id(1, true)
		if lobby.arena and lobby.arena.joined and not saw_chain:
			saw_chain = true
			release_at = Time.get_ticks_msec() + 200
		if saw_chain and not host and lobby.arena.local_slot == 1 and release_at > 0 and Time.get_ticks_msec() >= release_at:
			release_at = 0
			var key := InputEventKey.new()
			key.physical_keycode = KEY_X
			key.pressed = true
			Input.parse_input_event(key)
		if saw_chain and lobby.arena and not lobby.arena.joined:
			print("PASS room discovered, arena started, chain joined and released by guest ", lobby.multiplayer.get_unique_id())
			await create_timer(0.7 if host else 0.5).timeout
			quit(0)
			return
	printerr("Lobby timed out ", lobby.status)
	quit(1)
