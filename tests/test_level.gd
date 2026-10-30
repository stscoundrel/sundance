extends SceneTree
## Level sanity checks:  godot --headless --path . -s tests/test_level.gd
## The hero must start out of every bandit's reach: further than the longest
## (wary) sight range from every bandit post and patrol point, and not inside an object.

const SAFE_DIST := 300.0

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _init() -> void:
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town.json"))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/meta.json"))
	var g := Vector2(level["player"]["x"], level["player"]["y"])
	var spawn := Iso.to_screen(g)
	var sight := Enemy.VIEW * 1.2
	check(SAFE_DIST > sight, "safe distance exceeds the wary sight range")
	for e in level["enemies"]:
		var pts := [Vector2(e["x"], e["y"])]
		for p in e.get("patrol", []):
			pts.append(Vector2(p[0], p[1]))
		for p in pts:
			var d := spawn.distance_to(Iso.to_screen(p))
			check(d > SAFE_DIST, "%s at %s is only %d px from the spawn" % [e["kind"], p, d])
	for o in level["objects"]:
		var m: Dictionary = meta["objects"][o["type"]]
		if m["collide"] == "none":
			continue
		var r := Rect2(Vector2(o["x"], o["y"]), Vector2(m["footprint"][0], m["footprint"][1])).grow(0.3)
		check(not r.has_point(g), "spawn overlaps %s" % o["type"])
	print("level: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
