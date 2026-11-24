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
		print("ROOM ", lobby.room_code)
	else:
		lobby.get_node("Center/Menu/Address").text = OS.get_cmdline_user_args()[0]
		lobby.join_room()
	var deadline := Time.get_ticks_msec() + 9000
	var sent := false
	var voted := false
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if lobby.members.size() != expected:
			continue
		if not sent:
			lobby.toggle_ready()
			sent = true
		if host and not lobby.arena and lobby.members.values().all(func(member): return member.ready):
			lobby.start_match()
		if lobby.arena and not voted:
			voted = true
			if host:
				lobby.arena.act(0, true)
			else:
				lobby.arena.action.rpc_id(1, true)
		if lobby.arena and lobby.arena.joined:
			print("PASS room discovered, arena started, chain joined ", lobby.multiplayer.get_unique_id())
			await create_timer(0.7 if host else 0.5).timeout
			quit(0)
			return
	printerr("Lobby timed out ", lobby.status)
	quit(1)
