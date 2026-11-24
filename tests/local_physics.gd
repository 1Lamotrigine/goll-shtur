extends SceneTree

var failures := 0
var targets: Array[int] = []

func check(ok: bool, title: String) -> void:
	print("PASS " if ok else "FAIL ", title)
	if not ok:
		failures += 1

func _initialize() -> void:
	run.call_deferred()

func ticks(n: int) -> void:
	for i in n:
		await physics_frame

func run() -> void:
	var arena = load("res://levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	var body = arena.get_node("Polygon")
	body.pull_accepted.connect(func(_i, target): targets.append(target))
	await ticks(120)
	check(absf(body.position.y - 0.525) < 0.05, "gravity and floor")
	Input.action_press("pull_0")
	await ticks(4)
	check(targets == [1] and body.angular_velocity.length() > 0.1, "single pull and tilt")
	await ticks(20)
	check(targets.size() == 1, "held input")
	Input.action_release("pull_0")
	Input.action_press("reset")
	await ticks(2)
	Input.action_release("reset")
	check(body.position.distance_to(body.spawn.origin) < 0.02 and body.angular_velocity.length() < 0.01 and absf(body.linear_velocity.y) < 0.35, "reset")
	targets.clear()
	for action in body.ACTIONS:
		Input.action_press(action)
	await ticks(3)
	check(targets == [1,2,3,0] and body.linear_velocity.y > 9 and body.angular_velocity.length() < 0.01, "symmetric launch and wrapping")
	for action in body.ACTIONS:
		Input.action_release(action)
	await ticks(10)
	body.request_pull(0)
	await ticks(10)
	var direction: Vector3 = body.global_basis.y.slide(Vector3.UP).normalized()
	var before: Vector3 = body.linear_velocity
	body.request_pull(1)
	await ticks(2)
	var change: Vector3 = body.linear_velocity - before
	check(change.dot(direction) > 0.05, "steering follows tilt in flight")
	quit(1 if failures else 0)
