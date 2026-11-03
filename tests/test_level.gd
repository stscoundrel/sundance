extends SceneTree
## Level sanity checks:  godot --headless --path . -s tests/test_level.gd
## The hero must start out of every bandit's sight: from every bandit post and
## patrol point the spawn is either beyond the longest (wary) sight range or behind
## a wall. And he mustn't start inside an object.

var failures := 0
var game: Node
var frame := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false   # let the walls settle into the physics world
	var level: Dictionary = game.level
	var meta: Dictionary = game.meta
	var g := Vector2(level["player"]["x"], level["player"]["y"])
	var spawn := Iso.to_screen(g)
	var sight := Enemy.VIEW * 1.2
	var nearest := INF
	for e in level["enemies"]:
		var pts := [Vector2(e["x"], e["y"])]
		for p in e.get("patrol", []):
			pts.append(Vector2(p[0], p[1]))
		for p in pts:
			var at := Iso.to_screen(p)
			var d := spawn.distance_to(at)
			nearest = minf(nearest, d)
			check(d > sight or not game.line_of_sight(at, spawn, false),
				"%s at %s can see the spawn from %d px" % [e["kind"], p, d])
	for o in level["objects"]:
		var m: Dictionary = meta["objects"][o["type"]]
		if m["collide"] == "none":
			continue
		var r := Rect2(Vector2(o["x"], o["y"]), Vector2(m["footprint"][0], m["footprint"][1])).grow(0.3)
		check(not r.has_point(g), "spawn overlaps %s" % o["type"])
	check(game.is_free(spawn), "spawn is not on open ground")
	print("spawn at %s, nearest bandit post %.0f px away" % [g, nearest])
	print("level: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
