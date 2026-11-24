extends Control

var peer: ENetMultiplayerPeer
var members := {}
const WIRE_VERSION := 7
var map_type := 0
var status := ""
var room_code := ""
var discovery := PacketPeerUDP.new()
var searching := ""
var search_until := 0
var next_query := 0
var arena: Node3D
const DISCOVERY_GROUP := "239.255.42.68"
const DISCOVERY_PORT := 24568
const COLORS := ["Красный", "Синий", "Оранжевый", "Зелёный", "Фиолетовый", "Жёлтый"]

func _ready() -> void:
	$Center/Menu/Map.add_item("Карта · Луг")
	$Center/Menu/Map.add_item("Карта · Big Stair")
	$Center/Menu/Map.item_selected.connect(func(index: int):
		if peer and multiplayer.is_server():
			map_type = index
			publish()
	)
	$Center/Menu/Training.pressed.connect(func(): get_tree().change_scene_to_file("res://levels/test_arena.tscn"))
	$Center/Menu/Quit.pressed.connect(func(): get_tree().quit())
	$Center/Menu/Host.pressed.connect(host_room)
	$Center/Menu/Join.pressed.connect(join_room)
	$Center/Menu/Leave.pressed.connect(close_room.bind("Вы вышли из комнаты"))
	$Center/Menu/Ready.pressed.connect(toggle_ready)
	multiplayer.connected_to_server.connect(func(): register_player.rpc_id(1, $Center/Menu/Nick.text, WIRE_VERSION))
	multiplayer.connection_failed.connect(close_room.bind("Не удалось подключиться к хосту"))
	multiplayer.server_disconnected.connect(close_room.bind("Хост закрыл комнату"))
	multiplayer.peer_disconnected.connect(remove_player)
	$Center/Menu/Start.pressed.connect(start_match)
	$Center/Menu/Copy.pressed.connect(func(): DisplayServer.clipboard_set(room_code))
	$Center/Menu/Address.placeholder_text = "Код комнаты или IP:порт"
	$Center/Menu/Port.prefix = "UDP "
	$Center/Menu.custom_minimum_size.x = 340
	refresh()

func host_room() -> void:
	var candidate := ENetMultiplayerPeer.new()
	if candidate.create_server(int($Center/Menu/Port.value), COLORS.size() - 1) != OK:
		status = "Не удалось открыть UDP-порт"
		refresh()
		return
	var discovery_available := discovery.bind(DISCOVERY_PORT, "0.0.0.0") == OK
	if discovery_available:
		for interface in IP.get_local_interfaces():
			for address: String in interface.addresses:
				if "." in address and not address.begins_with("127."):
					discovery.join_multicast_group(DISCOVERY_GROUP, interface.name)
					break
	room_code = "%06d" % randi_range(0, 999999) if discovery_available else ""
	peer = candidate
	multiplayer.multiplayer_peer = peer
	status = "Код комнаты " + room_code if discovery_available else "Поиск по коду недоступен"
	for address in IP.get_local_addresses():
		if "." in address and not address.begins_with("127.") and not ":" in address:
			status += "\nАдрес для входа: %s:%d" % [address, int($Center/Menu/Port.value)]
	add_player(1, $Center/Menu/Nick.text)

func join_room() -> void:
	var address: String = $Center/Menu/Address.text.strip_edges()
	if address.length() == 6 and address.is_valid_int() and address == "%06d" % address.to_int():
		if discovery.bind(0, "0.0.0.0") != OK:
			status = "Не удалось открыть поиск"
		else:
			discovery.set_broadcast_enabled(true)
			searching = address
			search_until = Time.get_ticks_msec() + 5000
			next_query = 0
			status = "Поиск комнаты в локальной сети…"
		refresh()
		return
	var port := int($Center/Menu/Port.value)
	if address.count(":") == 1:
		var port_text := address.get_slice(":", 1)
		port = port_text.to_int() if port_text.is_valid_int() else 0
		address = address.get_slice(":", 0)
	connect_address(address, port)

func connect_address(address: String, port: int) -> void:
	var candidate := ENetMultiplayerPeer.new()
	if port < 1 or port > 65535 or not address.is_valid_ip_address() or candidate.create_client(address, port) != OK:
		status = "Проверьте IP и порт хоста"
		refresh()
		return
	peer = candidate
	multiplayer.multiplayer_peer = peer
	status = "Подключение…"
	refresh()

func close_room(message: String) -> void:
	end_match()
	discovery.close()
	searching = ""
	room_code = ""
	if peer:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		peer.close()
		peer = null
	members.clear()
	map_type = 0
	status = message
	refresh()

@rpc("any_peer", "reliable")
func register_player(nickname: String, version := 0) -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		if version != WIRE_VERSION:
			peer.disconnect_peer(id)
			status = "Версии сети различаются. Обновите игру у обоих игроков."
			refresh()
			return
		add_player(id, nickname)

func add_player(id: int, nickname: String) -> void:
	if members.has(id) or members.size() >= COLORS.size() or arena:
		return
	var used := []
	for member in members.values():
		used.append(member.slot)
	for slot in COLORS.size():
		if slot not in used:
			var display_name := nickname.strip_edges().left(24).replace("\n", " ")
			members[id] = {"slot":slot, "name":display_name if display_name else "Игрок %d" % (slot + 1), "ready":false}
			break
	reset_readiness()

func remove_player(id: int) -> void:
	if peer and multiplayer.is_server() and members.erase(id):
		end_match()
		reset_readiness.call_deferred()

func reset_readiness() -> void:
	if not peer:
		return
	for member in members.values():
		member.ready = false
	publish()

func toggle_ready() -> void:
	if multiplayer.is_server():
		change_ready(1)
	else:
		request_ready_toggle.rpc_id(1)

@rpc("any_peer", "reliable")
func request_ready_toggle() -> void:
	if multiplayer.is_server():
		change_ready(multiplayer.get_remote_sender_id())

func change_ready(id: int) -> void:
	if members.has(id):
		members[id].ready = not members[id].ready
		publish()

func publish() -> void:
	room_state.rpc(members, room_code, map_type)
	refresh()

@rpc("authority", "reliable")
func room_state(roster: Dictionary, code: String, selected_map: int) -> void:
	map_type = selected_map
	members = roster
	room_code = code
	if arena and arena.members.size() != members.size():
		end_match()
	status = "Код комнаты " + code
	refresh()

func refresh() -> void:
	$Center/Menu/Map.visible = peer != null
	$Center/Menu/Map.disabled = peer == null or not multiplayer.is_server()
	$Center/Menu/Map.select(map_type)
	for control in [$Center/Menu/Host, $Center/Menu/Join, $Center/Menu/Nick, $Center/Menu/Address, $Center/Menu/Port, $Center/Menu/Training]:
		control.visible = peer == null and searching.is_empty()
	$Center/Menu/Ready.visible = peer != null and members.has(multiplayer.get_unique_id())
	$Center/Menu/Leave.visible = peer != null or not searching.is_empty()
	$Center/Menu/Copy.visible = not room_code.is_empty()
	$Center/Menu/Start.visible = peer != null and multiplayer.is_server()
	$Center/Menu/Start.disabled = members.size() < 2 or not members.values().all(func(m): return m.ready)
	var lines := PackedStringArray([status])
	if peer and not members.is_empty():
		var slots := ["—", "—", "—", "—", "—", "—"]
		for member in members.values():
			slots[member.slot] = "%s · %s" % [member.name, "готов" if member.ready else "ожидание"]
		for i in COLORS.size():
			lines.append("%s · %s" % [COLORS[i], slots[i]])
	$Center/Menu/Roster.text = "\n".join(lines)

func _process(_delta: float) -> void:
	if not discovery.is_bound():
		return
	var now := Time.get_ticks_msec()
	if not searching.is_empty() and now >= search_until:
		close_room("Комната не найдена. Введите адрес IP:порт с экрана хоста.")
		return
	if not searching.is_empty() and now >= next_query:
		next_query = now + 500
		for destination in [DISCOVERY_GROUP, "255.255.255.255", "127.0.0.1"]:
			if discovery.set_dest_address(destination, DISCOVERY_PORT) == OK:
				discovery.put_packet(("GP1?" + searching).to_ascii_buffer())
	for i in mini(32, discovery.get_available_packet_count()):
		var msg := discovery.get_packet().get_string_from_ascii()
		var ip := discovery.get_packet_ip()
		if peer and multiplayer.is_server() and msg == "GP1?" + room_code:
			discovery.set_dest_address(ip, discovery.get_packet_port())
			discovery.put_packet(("GP1!%s/%d" % [room_code, int($Center/Menu/Port.value)]).to_ascii_buffer())
		elif not searching.is_empty() and msg.begins_with("GP1!" + searching + "/"):
			var port := msg.get_slice("/", 1).to_int()
			if port > 0 and port <= 65535:
				searching = ""
				discovery.close()
				connect_address(ip, port)
				return

func start_match() -> void:
	if multiplayer.is_server() and members.size() >= 2 and members.values().all(func(m): return m.ready):
		peer.refuse_new_connections = true
		open_arena.rpc(map_type, randi())

@rpc("authority", "call_local", "reliable")
func open_arena(selected_map: int, layout_seed: int) -> void:
	if arena:
		return
	arena = preload("res://levels/test_arena.tscn").instantiate()
	arena.set_script(preload("res://levels/network_arena.gd"))
	if selected_map == 1:
		for child_name in ["Meadow", "OuterMeadow", "Floor"]:
			arena.get_node(child_name).free()
		var stairs := arena.get_node("SkyCourse")
		stairs.set_script(preload("res://levels/big_stair.gd"))
		stairs.set("layout_seed", layout_seed)
	arena.name = "OnlineArena"
	arena.members = members.duplicate(true)
	var ids := members.keys()
	ids.sort_custom(func(a, b): return members[a].slot < members[b].slot)
	var colors := PackedInt32Array()
	for i in ids.size():
		colors.append(members[ids[i]].slot)
		arena.members[ids[i]].slot = i
	arena.get_node("Polygon").color_slots = colors
	arena.get_node("Polygon").local_slot = arena.members[multiplayer.get_unique_id()].slot
	add_child(arena)
	$Background.hide()
	$Center.hide()

func end_match() -> void:
	if arena:
		if peer and multiplayer.is_server():
			peer.refuse_new_connections = false
		remove_child(arena)
		arena.queue_free()
		arena = null
		$Background.show()
		$Center.show()
