extends SceneTree
## What a blast leaves on the walls (San Miguel, bandits out of town):
##   front  - a stick going off in the street before the hotel blackens its front and
##            knocks a hole in it, rubble heaped in the dirt below; only a look: the
##            wall still stops rounds, and there's no more of it to collide with.
##   back   - one behind the hotel leaves its front as it was (a face you never see
##            takes no mark).
##   sizes  - at the same distance from a wall, a keg's blast marks it worse than a
##            stick's, and a crate's worse than a keg's.
##   stays  - once it's quiet and the town has swept and mended, the wounds and the
##            rubble are still there; no more than a building's worth are kept.
##   godot --headless --path . --fixed-fps 60 -s tests/test_wounds.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var hotel: Sprite2D
var bits := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_reserve", true)
	seed(15)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.quiet_after = 2.0
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_front()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("wounds test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _wounds(spr: Sprite2D) -> Wounds:
	return spr.get_node_or_null("Wounds") if spr else null


## The building whose wall a ray along the ground from `from` to `to` (tiles) strikes.
func _wall(from: Vector2, to: Vector2) -> Dictionary:
	return game.ray(Iso.to_screen(from), Iso.to_screen(to), Iso.LAYER_WALL)


func _front() -> void:
	step = "front"
	var hit := _wall(Vector2(32.0, 31.0), Vector2(32.0, 26.0))   # the hotel's front, on main street
	check(not hit.is_empty() and hit["collider"].has_meta("building"), "no hotel front to blow up")
	if hit.is_empty():
		return
	hotel = hit["collider"].get_meta("building")
	var shapes: int = hit["collider"].get_child_count()
	game.blast(hit["position"] + Vector2(0, 14), game.player)
	var w := _wounds(hotel)
	check(w != null and w.list.size() >= 1, "the blast left no mark on the hotel")
	if w:
		var biggest: float = w.list.map(func(x): return x["size"]).max()
		print("hotel: %d wound(s), the worst %.2f; rubble bits %d" % [w.list.size(), biggest, game.rubble.bits.size()])
		check(biggest >= Wounds.HOLE, "right by the wall, and no hole in it (%.2f)" % biggest)
		check(not w.adobe, "the hotel's timber, not mud brick")
		check(w.texture == hotel.texture and w.offset == hotel.offset and w.clip_children == CanvasItem.CLIP_CHILDREN_ONLY,
			"the wounds aren't clipped to the building")
		for x in w.list:   # all on the street side
			check(Iso.to_grid(hotel.position + x["at"]).y > 27.0, "a wound round the back")
	bits = game.rubble.bits.size()
	check(bits > 0, "no rubble in the street")
	check(hit["collider"].get_child_count() == shapes, "the wall's shape changed")
	var again := _wall(Vector2(32.0, 31.0), Vector2(32.0, 26.0))
	check(again.get("collider") == hit["collider"], "the wall no longer stops a round")
	check(not game.line_of_sight(Iso.to_screen(Vector2(32, 31)), Iso.to_screen(Vector2(32, 22)), false),
		"you can see through the hotel now")
	queue.append([0.5, _back])


func _back() -> void:
	step = "back"
	var w := _wounds(hotel)
	var n := w.list.size()
	var sizes: Array = w.list.map(func(x): return x["size"])
	var hit := _wall(Vector2(31.0, 20.0), Vector2(31.0, 25.0))   # its back wall, from the yard behind
	check(hit.get("collider") and hit["collider"].get_meta("building") == hotel, "no back wall to the hotel there")
	if hit.get("collider"):
		game.blast(hit["position"] + Vector2(0, -12), game.player)
	check(w.list.size() == n and w.list.map(func(x): return x["size"]) == sizes, "a blast round the back marked the front")
	queue.append([0.5, _sizes])


func _sizes() -> void:
	step = "sizes"
	# three fronts with a clear piece of street before them, each blown at the same
	# distance: a stick, a keg (110 px), a crate (150 px)
	var fronts: Array[Dictionary] = []
	for b in game.buildings:
		var spr: Sprite2D = b["sprite"]
		if _wounds(spr) != null:
			continue
		var mid: float = (b["x0"] + b["x1"]) * 0.5
		var hit := _wall(Vector2(mid, b["y1"] + 2.0), Vector2(mid, b["y1"] - 0.5))
		if hit.is_empty() or not hit["collider"].has_meta("building") or hit["collider"].get_meta("building") != spr:
			continue
		if fronts.any(func(f): return f["spr"].position.distance_to(spr.position) < 400.0):
			continue   # (far enough apart that one blast doesn't reach the next)
		fronts.append({"spr": spr, "at": hit["position"]})
		if fronts.size() == 3:
			break
	check(fronts.size() == 3, "only %d fronts to try" % fronts.size())
	if fronts.size() < 3:
		return
	var worst: Array[float] = []
	for i in 3:
		var kind: Dictionary = [{"r": Dynamite.R, "core": Dynamite.CORE}, Charge.KINDS["keg"], Charge.KINDS["dyn_crate"]][i]
		var r: float = kind["r"]
		var core: float = kind["core"]
		game.blast(fronts[i]["at"] + Vector2(0, 20), game.player, r, core)
		var w := _wounds(fronts[i]["spr"])
		worst.append(w.list.map(func(x): return x["size"]).max() if w else 0.0)
	print("stick %.2f, keg %.2f, crate %.2f" % worst)
	check(worst[0] > 0.0 and worst[0] < worst[1] and worst[1] < worst[2], "the bigger bang didn't mark worse")
	queue.append([120.0, _stays])


func _stays() -> void:
	step = "stays"
	var w := _wounds(hotel)
	check(w != null and w.list.size() >= 1, "the hotel's wounds were mended")
	print("swept: %s, repaired: %s; rubble %d of %d" % [game.stats.get("swept", 0), game.stats.get("repaired", 0),
		game.rubble.bits.size(), bits])
	check(game.rubble.bits.size() >= bits, "the rubble was swept away")
	if w:
		for i in 40:
			w.add(Vector2(i * 30.0, 0), Vector2(-0.45, 0.9), 1.0)
		check(w.list.size() == Wounds.MAX, "%d wounds kept" % w.list.size())
	check(game.meta["objects"]["wall_x8"]["paint"] == "adobe" and game.meta["objects"]["chapel"]["paint"] == "adobe",
		"the fort's walls aren't mud brick")
