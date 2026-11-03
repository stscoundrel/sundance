extends SceneTree
## Bandits hunting the stranger's last position shouldn't all file down the same
## route: some should go round the other side of a building to cut him off.
## SEED=n picks the random seed; NO_FLANK=1 is the control run with no flanking.
##   godot --headless --path . --fixed-fps 60 -s tests/test_flank.gd

const TARGET := Vector2(31.0, 19.2)    # the yard behind the hotel: an alley on either side, or the north street
const HIDE_AT := Vector2(1.0, 62.5)

var game: Node
var frame := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _sample(route: PackedVector2Array, from: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var prev := from
	for p in route:
		var n := int(prev.distance_to(p) / 6.0) + 1
		for k in n:
			out.append(prev.lerp(p, float(k) / n))
		prev = p
	return out


## The direction a route closes in on the target from.
func _approach(pts: PackedVector2Array, target: Vector2) -> Vector2:
	for k in range(pts.size() - 1, -1, -1):
		if pts[k].distance_to(target) > 55.0:
			return (pts[k] - target).normalized()
	return Vector2.ZERO


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(HIDE_AT)
		game.player.hp = 1000000
		var target := Iso.to_screen(TARGET)
		for e in game.enemies:
			if OS.get_environment("NO_FLANK") != "":
				e.tdata["flank"] = 0.0   # control run: nobody flanks
			if e.global_position.distance_to(target) < 420.0 and e.kind != "poacher":
				e.enter_combat(target, false, false)
	if frame < 60:
		return false
	var target := Iso.to_screen(TARGET)
	var routes := []
	var roles := {}
	for e in game.enemies:
		if e.alive and e.hunt_role != "":
			routes.append([e, _sample(e.path, e.global_position)])
			roles[e.hunt_role] = roles.get(e.hunt_role, 0) + 1
			if e.hunt_role == "flank" and e.path.size() > 0:
				check(e.path[e.path.size() - 1].distance_to(target) < 90.0, "a flanker heads somewhere else entirely")
	# Each flanker must close in from a different side than the comrades who set off
	# near him before he did (the ones he'd otherwise follow), and not by a
	# ridiculous detour.
	var dump := []
	for r in routes:
		dump.append({"role": r[0].hunt_role, "points": Array(r[1]).map(func(v): return [v.x, v.y])})
	var apart := 0
	var flankers := 0
	var worst_ratio := 0.0
	var plans: Array = game.hunts
	for i in plans.size():
		var h: Dictionary = plans[i]
		if h["role"] != "flank" or h["target"].distance_to(target) > 100.0:
			continue
		flankers += 1
		var mine: Vector2 = game.approach_dir(h["path"], target)
		var own: Vector2 = game.approach_dir(game.find_path(h["from"], target), target)
		var ok: bool = abs(mine.angle_to(own)) > deg_to_rad(50.0)
		if ok:
			apart += 1
		var straight: float = game._length(h["from"], game.find_path(h["from"], target))
		worst_ratio = max(worst_ratio, game._length(h["from"], h["path"]) / max(straight, 1.0))
	var out := FileAccess.open("user://flank_routes.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"target": [target.x, target.y], "routes": dump}))
	# What matters on screen: a group of bandits setting off together shouldn't file
	# down one route. For each group of three or more starting within 220 px of each
	# other, do they close in from at least two clearly different sides? Flanking is
	# a chance per bandit and the streets limit the choices, so not every group will,
	# but most should (without flanking about half go single file; with it, about a
	# quarter: NO_FLANK=1 runs the control).
	var groups := 0
	var single_file := 0
	for h in plans:
		var mates := plans.filter(func(o): return o["from"].distance_to(h["from"]) < 220.0 and o["target"].distance_to(target) < 100.0)
		if mates.size() < 3:
			continue
		groups += 1
		var dirs := mates.map(func(o): return game.approach_dir(o["path"], target))
		var spread := 0.0
		for x in dirs:
			for y in dirs:
				spread = max(spread, abs(x.angle_to(y)))
		if spread < deg_to_rad(50.0):
			single_file += 1
	print("hunters: %s, real flanks %d of %d, groups of 3+ %d, of which single file %d, longest detour %.1fx" % [
		roles, apart, flankers, groups, single_file, worst_ratio])
	check(apart == flankers, "%d flankers follow the others in" % (flankers - apart))
	check(roles.get("flank", 0) == flankers, "a hunter was told to flank but has no flanking plan")
	check(single_file * 2 <= groups, "%d of %d groups file down a single route" % [single_file, groups])
	check(worst_ratio < 2.2, "a flanker takes a ridiculous detour")
	print("flank test: ", "OK" if failures == 0 else "%d failures" % failures)
	return true
